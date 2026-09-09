@Tags(['onepub_command', 'integration', 'staging'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:dcli/dcli.dart';
import 'package:onepub/src/util/one_pub_token_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'staging_common.dart';

class _StressSummary {
  final int workers;
  final int requestsPerWorker;
  final int successes;
  final int bytes;
  final Map<int, int> statuses;

  _StressSummary({
    required this.workers,
    required this.requestsPerWorker,
    required this.successes,
    required this.bytes,
    required this.statuses,
  });

  int get totalRequests => workers * requestsPerWorker;
  int get failures => totalRequests - successes;
}

void main() {
  final config = StagingConfig.fromEnv();

  test('download stress: authenticated archive downloads', () async {
    await withAdmin(config, (context) async {
      final published = await publishAndVerify(
        context,
        config,
        largeNativeAssetMb: config.downloadStressPackageSizeMb,
      );
      final archiveUrl = published.versionsBody.versions
          .firstWhere((v) => v.version == published.version)
          .archiveUrl;
      final token = await OnePubTokenStore().load();

      late final _StressSummary summary;
      try {
        summary = await _runStressWorkers(
          workerCount: config.downloadStressConcurrency < 1
              ? 1
              : config.downloadStressConcurrency,
          requestsPerWorker: config.downloadStressRequests < 1
              ? 1
              : config.downloadStressRequests,
          archiveUrl: archiveUrl,
          token: token,
        );
      } finally {
        // This test deliberately exhausts the download limiter. Do not leak
        // that state into the next test file in a serial system-test run.
        await _waitForArchiveRecovery(
          archiveUrl: archiveUrl,
          token: token,
        );
        await waitForCliRateLimitRecovery();
      }

      stdout.writeln('''
Download stress workers=${summary.workers}
requestsPerWorker=${summary.requestsPerWorker}
totalRequests=${summary.totalRequests}
successes=${summary.successes}
failures=${summary.failures}
bytes=${summary.bytes}
statusBuckets=${summary.statuses}
''');

      expect(summary.successes, greaterThan(0),
          reason: 'Stress test did not complete any successful downloads.');
    });
  },
      timeout: const Timeout(Duration(hours: 1)),
      skip: config.skipDownloadStress || config.skipPublish);
}

Future<_StressSummary> _runStressWorkers({
  required int workerCount,
  required int requestsPerWorker,
  required String archiveUrl,
  required String token,
}) async {
  await _waitForArchiveRecovery(
    archiveUrl: archiveUrl,
    token: token,
  );

  final workerPort = ReceivePort();
  final exitPort = ReceivePort();
  final done = Completer<_StressSummary>();
  final isolates = <Isolate>[];
  final statuses = <int, int>{};

  var active = 0;
  var successes = 0;
  var bytes = 0;
  Object? firstError;

  workerPort.listen((message) {
    final data = message as Map<dynamic, dynamic>;
    switch (data['type'] as String) {
      case 'progress':
        final statusCode = data['statusCode'] as int;
        statuses[statusCode] = (statuses[statusCode] ?? 0) + 1;
        if (statusCode == 200) {
          successes++;
          bytes += data['bytes'] as int;
        }
      case 'error':
        firstError ??= StateError(data['message'] as String);
        for (final isolate in isolates) {
          isolate.kill(priority: Isolate.immediate);
        }
    }
  });

  exitPort.listen((_) {
    active--;
    if (active <= 0 && !done.isCompleted) {
      workerPort.close();
      exitPort.close();
      if (firstError != null) {
        done.completeError(firstError!);
      } else {
        done.complete(_StressSummary(
          workers: workerCount,
          requestsPerWorker: requestsPerWorker,
          successes: successes,
          bytes: bytes,
          statuses: statuses,
        ));
      }
    }
  });

  for (var i = 0; i < workerCount; i++) {
    active++;
    final isolate = await Isolate.spawn(
      _stressWorkerEntry,
      <String, Object>{
        'id': i + 1,
        'requestsPerWorker': requestsPerWorker,
        'archiveUrl': archiveUrl,
        'token': token,
        'sendPort': workerPort.sendPort,
      },
      onExit: exitPort.sendPort,
    );
    isolates.add(isolate);
  }

  return done.future;
}

Future<void> _waitForArchiveRecovery({
  required String archiveUrl,
  required String token,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final started = DateTime.now();
  final probeDir =
      await Directory.systemTemp.createTemp('onepub_download_stress_probe_');

  try {
    while (DateTime.now().difference(started) < timeout) {
      final result = await _downloadArchive(
        archiveUrl: archiveUrl,
        token: token,
        saveToPath: p.join(probeDir.path, 'probe.tar.gz'),
      );
      if (result.statusCode == 200) {
        return;
      }
      await sleepAsync(1);
    }
    throw StateError(
      'Archive download rate limit did not recover within '
      '${timeout.inSeconds} seconds.',
    );
  } finally {
    if (probeDir.existsSync()) {
      await probeDir.delete(recursive: true);
    }
  }
}

Future<void> _stressWorkerEntry(Map<String, Object> args) async {
  final id = args['id']! as int;
  final requestsPerWorker = args['requestsPerWorker']! as int;
  final archiveUrl = args['archiveUrl']! as String;
  final token = args['token']! as String;
  final sendPort = args['sendPort']! as SendPort;
  final tempDir =
      await Directory.systemTemp.createTemp('onepub_download_stress_$id');

  try {
    for (var attempt = 0; attempt < requestsPerWorker; attempt++) {
      final status = await _downloadArchive(
        archiveUrl: archiveUrl,
        token: token,
        saveToPath: p.join(tempDir.path, 'archive_$attempt.tar.gz'),
      );
      sendPort.send(<String, Object>{
        'type': 'progress',
        'statusCode': status.statusCode,
        'bytes': status.bytes,
      });
    }
  } catch (e) {
    sendPort.send(<String, Object>{
      'type': 'error',
      'message': 'Download stress worker $id failed: $e',
    });
  } finally {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  }
}

Future<({int statusCode, int bytes})> _downloadArchive({
  required String archiveUrl,
  required String token,
  required String saveToPath,
}) async {
  try {
    await fetch(
      url: archiveUrl,
      saveToPath: saveToPath,
      headers: <String, String>{'authorization': token},
    );
    return (statusCode: 200, bytes: File(saveToPath).lengthSync());
  } on FetchException catch (e) {
    final statusCode = e.errorCode ?? 0;
    if (exists(saveToPath)) {
      delete(saveToPath);
    }
    return (statusCode: statusCode, bytes: 0);
  }
}
