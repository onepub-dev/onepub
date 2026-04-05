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

class _FlowStressSummary {
  final int workers;
  final int requestsPerWorker;
  final int successfulFlows;
  final int archiveBytes;
  final Map<int, int> metadataStatuses;
  final Map<int, int> versionStatuses;
  final Map<int, int> archiveStatuses;

  _FlowStressSummary({
    required this.workers,
    required this.requestsPerWorker,
    required this.successfulFlows,
    required this.archiveBytes,
    required this.metadataStatuses,
    required this.versionStatuses,
    required this.archiveStatuses,
  });

  int get totalFlows => workers * requestsPerWorker;
  int get failedFlows => totalFlows - successfulFlows;
}

void main() {
  final config = StagingConfig.fromEnv();

  test('download stress: pub API flow', () async {
    await withAdmin(config, (context) async {
      final published = await publishAndVerify(
        context,
        config,
        largeNativeAssetMb: config.downloadStressPackageSizeMb,
      );
      final token = await OnePubTokenStore().load();
      final orgId = context.settings.obfuscatedOrganisationId;
      final base = context.onepubUrl.endsWith('/')
          ? context.onepubUrl.substring(0, context.onepubUrl.length - 1)
          : context.onepubUrl;
      final metadataUrl = '$base/api/$orgId/api/packages/${published.name}';
      final versionUrl = '$metadataUrl/versions/${published.version}';
      final archiveUrl = published.versionsBody.versions
          .firstWhere((v) => v.version == published.version)
          .archiveUrl;

      final summary = await _runFlowStressWorkers(
        workerCount: config.downloadStressConcurrency < 1
            ? 1
            : config.downloadStressConcurrency,
        requestsPerWorker: config.downloadStressRequests < 1
            ? 1
            : config.downloadStressRequests,
        metadataUrl: metadataUrl,
        versionUrl: versionUrl,
        archiveUrl: archiveUrl,
        token: token,
      );

      stdout.writeln('''
Download pub flow stress workers=${summary.workers}
requestsPerWorker=${summary.requestsPerWorker}
totalFlows=${summary.totalFlows}
successfulFlows=${summary.successfulFlows}
failedFlows=${summary.failedFlows}
archiveBytes=${summary.archiveBytes}
metadataStatuses=${summary.metadataStatuses}
versionStatuses=${summary.versionStatuses}
archiveStatuses=${summary.archiveStatuses}
''');

      expect(summary.successfulFlows, greaterThan(0), reason: '''
Mixed pub API stress test did not complete any successful flows.''');
    });
  },
      timeout: const Timeout(Duration(hours: 1)),
      skip: config.skipDownloadStress || config.skipPublish);
}

Future<_FlowStressSummary> _runFlowStressWorkers({
  required int workerCount,
  required int requestsPerWorker,
  required String metadataUrl,
  required String versionUrl,
  required String archiveUrl,
  required String token,
}) async {
  await _waitForPubFlowRecovery(
    metadataUrl: metadataUrl,
    versionUrl: versionUrl,
    archiveUrl: archiveUrl,
    token: token,
  );

  final workerPort = ReceivePort();
  final exitPort = ReceivePort();
  final done = Completer<_FlowStressSummary>();
  final isolates = <Isolate>[];

  final metadataStatuses = <int, int>{};
  final versionStatuses = <int, int>{};
  final archiveStatuses = <int, int>{};

  var active = 0;
  var successfulFlows = 0;
  var archiveBytes = 0;
  Object? firstError;

  workerPort.listen((message) {
    final data = message as Map<dynamic, dynamic>;
    switch (data['type'] as String) {
      case 'progress':
        final metadataStatus = data['metadataStatus'] as int;
        final versionStatus = data['versionStatus'] as int;
        final archiveStatus = data['archiveStatus'] as int;

        metadataStatuses[metadataStatus] =
            (metadataStatuses[metadataStatus] ?? 0) + 1;
        versionStatuses[versionStatus] =
            (versionStatuses[versionStatus] ?? 0) + 1;
        archiveStatuses[archiveStatus] =
            (archiveStatuses[archiveStatus] ?? 0) + 1;

        if (metadataStatus == 200 &&
            versionStatus == 200 &&
            archiveStatus == 200) {
          successfulFlows++;
          archiveBytes += data['archiveBytes'] as int;
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
        done.complete(_FlowStressSummary(
          workers: workerCount,
          requestsPerWorker: requestsPerWorker,
          successfulFlows: successfulFlows,
          archiveBytes: archiveBytes,
          metadataStatuses: metadataStatuses,
          versionStatuses: versionStatuses,
          archiveStatuses: archiveStatuses,
        ));
      }
    }
  });

  for (var i = 0; i < workerCount; i++) {
    active++;
    final isolate = await Isolate.spawn(
      _flowStressWorkerEntry,
      <String, Object>{
        'id': i + 1,
        'requestsPerWorker': requestsPerWorker,
        'metadataUrl': metadataUrl,
        'versionUrl': versionUrl,
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

Future<void> _waitForPubFlowRecovery({
  required String metadataUrl,
  required String versionUrl,
  required String archiveUrl,
  required String token,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final started = DateTime.now();
  final probeDir =
      await Directory.systemTemp.createTemp('onepub_download_pub_flow_probe_');

  try {
    while (DateTime.now().difference(started) < timeout) {
      final metadataStatus = await _getStatus(url: metadataUrl, token: token);
      final versionStatus = await _getStatus(url: versionUrl, token: token);
      final archiveResult = await _downloadArchive(
        archiveUrl: archiveUrl,
        token: token,
        saveToPath: p.join(probeDir.path, 'probe.tar.gz'),
      );

      if (metadataStatus == 200 &&
          versionStatus == 200 &&
          archiveResult.statusCode == 200) {
        return;
      }

      await sleepAsync(1);
    }
  } finally {
    if (probeDir.existsSync()) {
      await probeDir.delete(recursive: true);
    }
  }
}

Future<void> _flowStressWorkerEntry(Map<String, Object> args) async {
  final id = args['id']! as int;
  final requestsPerWorker = args['requestsPerWorker']! as int;
  final metadataUrl = args['metadataUrl']! as String;
  final versionUrl = args['versionUrl']! as String;
  final archiveUrl = args['archiveUrl']! as String;
  final token = args['token']! as String;
  final sendPort = args['sendPort']! as SendPort;
  final tempDir = await Directory.systemTemp
      .createTemp('onepub_download_pub_flow_stress_$id');

  try {
    for (var attempt = 0; attempt < requestsPerWorker; attempt++) {
      final metadataStatus = await _getStatus(url: metadataUrl, token: token);
      final versionStatus = await _getStatus(url: versionUrl, token: token);
      final archiveResult = await _downloadArchive(
        archiveUrl: archiveUrl,
        token: token,
        saveToPath: p.join(tempDir.path, 'archive_$attempt.tar.gz'),
      );
      sendPort.send(<String, Object>{
        'type': 'progress',
        'metadataStatus': metadataStatus,
        'versionStatus': versionStatus,
        'archiveStatus': archiveResult.statusCode,
        'archiveBytes': archiveResult.bytes,
      });
    }
  } catch (e) {
    sendPort.send(<String, Object>{
      'type': 'error',
      'message': 'Download pub flow stress worker $id failed: $e',
    });
  } finally {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  }
}

Future<int> _getStatus({required String url, required String token}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    request.headers.set('authorization', token);
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
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
