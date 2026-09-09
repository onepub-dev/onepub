@Tags(['onepub_command', 'integration', 'staging'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:onepub/src/util/one_pub_token_store.dart';
import 'package:onepub/src/util/send_command.dart';
import 'package:test/test.dart';

import 'staging_common.dart';

const _downloadLimitMessage = 'Monthly download limit exceeded for your plan. '
    'Please upgrade your plan to download more packages.';
const _defaultRemainingDownloadsBeforeLimit = 8;

class _DownloadLimitTarget {
  final String plan;
  final int packageSizeMb;

  const _DownloadLimitTarget({
    required this.plan,
    required this.packageSizeMb,
  });
}

void main() {
  final config = StagingConfig.fromEnv();
  final overridePackageSizeMb = int.tryParse(
      Platform.environment['ONEPUB_DOWNLOAD_LIMIT_PACKAGE_SIZE_MB'] ?? '');
  final remainingDownloadsBeforeLimit = int.tryParse(
        Platform.environment['ONEPUB_DOWNLOAD_LIMIT_REMAINING_DOWNLOADS'] ?? '',
      ) ??
      _defaultRemainingDownloadsBeforeLimit;
  final targets = <_DownloadLimitTarget>[
    _DownloadLimitTarget(
      plan: 'free',
      packageSizeMb: overridePackageSizeMb ?? 9,
    ),
    _DownloadLimitTarget(
      plan: 'pro',
      packageSizeMb: overridePackageSizeMb ?? 9,
    ),
    _DownloadLimitTarget(
      plan: 'team',
      packageSizeMb: overridePackageSizeMb ?? 14,
    ),
  ];
  final provisioned = <String, ProvisionedTestOrganisation>{};
  var canProvision = false;

  setUpAll(() async {
    canProvision = await hasSystemAdminToken(config);
    if (!canProvision) {
      stdout.writeln(
        'Skipping download byte-limit setup: requires a system-admin token '
        'to provision test organisations.',
      );
      return;
    }
    for (final target in targets) {
      provisioned[target.plan] = await createProvisionedTestOrganisation(
        config,
        plan: target.plan,
      );
    }
  });

  for (final target in targets) {
    test('download limits: byte quota ${target.plan}', () async {
      if (!canProvision) {
        stdout.writeln(
          'Skipping byte-limit ${target.plan} test: requires a system-admin '
          'token to provision test organisations.',
        );
        return;
      }
      final organisation = provisioned[target.plan];
      if (organisation == null) {
        throw StateError('Provisioned ${target.plan} organisation missing.');
      }

      await withScopedOrganisationToken(
          onepubUrl: organisation.onepubUrl,
          operatorEmail: organisation.operatorEmail,
          organisationName: organisation.organisationName,
          organisationId: organisation.organisationId,
          token: organisation.onepubToken,
          action: (context) async {
            final published = await publishAndVerify(
              context,
              config,
              largeNativeAssetMb: target.packageSizeMb,
            );
            final seedBytes = _seedBytesForPlan(
              plan: target.plan,
              packageSizeMb: target.packageSizeMb,
              remainingDownloadsBeforeLimit: remainingDownloadsBeforeLimit,
            );
            await _seedDownloadUsage(seedBytes);
            final archiveUrl = published.versionsBody.versions
                .firstWhere((v) => v.version == published.version)
                .archiveUrl;

            final token = await OnePubTokenStore().load();
            final workers = config.downloadLimitConcurrency < 1
                ? 1
                : config.downloadLimitConcurrency;
            final summary = await _runDownloadWorkers(
              workerCount: workers,
              archiveUrl: archiveUrl,
              token: token,
            );
            final totalMb = summary.totalBytes / (1024 * 1024);

            stdout.writeln('''
plan=${organisation.plan}
organisationId=${organisation.organisationId}
packageSizeMB=${target.packageSizeMb}
seededDownloadBytes=$seedBytes
Download bytes workers=${summary.workers}
downloads=${summary.downloads}
totalBytes=${summary.totalBytes}
totalMB=${totalMb.toStringAsFixed(2)}
limited=${summary.limited}
recoverable429=${summary.recoverable429Count}
''');

            if (!summary.limited) {
              throw StateError(
                'Byte-limit ${target.plan} test did not trigger the monthly '
                'download-limit response.',
              );
            }
          });
    },
        timeout: const Timeout(Duration(hours: 2)),
        skip: config.skipDownloadLimit || config.skipPublish);
  }
}

Future<void> _seedDownloadUsage(int bytes) async {
  final response = await sendCommand(
    command: 'test/download/seed/$bytes',
    commandType: CommandType.cli,
    method: Method.post,
  );
  if (!response.success) {
    throw StateError(
      'Failed to seed download usage: HTTP ${response.status} '
      '${response.errorMessage}',
    );
  }
}

int _seedBytesForPlan({
  required String plan,
  required int packageSizeMb,
  required int remainingDownloadsBeforeLimit,
}) {
  final quotaGb = switch (plan) {
    'free' => 1,
    'pro' => 1,
    'team' => 2,
    _ => 1,
  };
  final quotaBytes = quotaGb * 1000 * 1000 * 1000;
  final marginBytes =
      packageSizeMb * 1000 * 1000 * remainingDownloadsBeforeLimit;
  final seeded = quotaBytes - marginBytes;
  return seeded < 0 ? 0 : seeded;
}

class _ArchiveDownloadResult {
  final bool limited;
  final bool recoverable429;
  final int bytes;
  final int? errorStatusCode;

  _ArchiveDownloadResult(
      {required this.limited,
      required this.recoverable429,
      required this.bytes,
      this.errorStatusCode});
}

class _DownloadSummary {
  final int workers;
  final int downloads;
  final int totalBytes;
  final int recoverable429Count;
  final bool limited;

  _DownloadSummary({
    required this.workers,
    required this.downloads,
    required this.totalBytes,
    required this.recoverable429Count,
    required this.limited,
  });
}

Future<_ArchiveDownloadResult> _downloadArchive(HttpClient client,
    String archiveUrl, String token, String limitMessage) async {
  final request = await client.getUrl(Uri.parse(archiveUrl));
  request.headers.set('authorization', token);
  final response = await request.close();

  if (response.statusCode == 429) {
    final body = await utf8.decoder.bind(response).join();
    return _ArchiveDownloadResult(
      limited: body.contains(limitMessage),
      recoverable429: !body.contains(limitMessage),
      bytes: 0,
    );
  }

  if (response.statusCode >= 400) {
    await response.drain<void>();
    return _ArchiveDownloadResult(
      limited: false,
      recoverable429: false,
      bytes: 0,
      errorStatusCode: response.statusCode,
    );
  }

  var bytes = 0;
  if (response.contentLength >= 0) {
    bytes = response.contentLength;
    await response.drain<void>();
  } else {
    await for (final chunk in response) {
      bytes += chunk.length;
    }
  }

  return _ArchiveDownloadResult(
    limited: false,
    recoverable429: false,
    bytes: bytes,
  );
}

Future<_DownloadSummary> _runDownloadWorkers({
  required int workerCount,
  required String archiveUrl,
  required String token,
}) async {
  final workerPort = ReceivePort();
  final exitPort = ReceivePort();
  final isolates = <Isolate>[];
  final done = Completer<_DownloadSummary>();

  var active = 0;
  var downloads = 0;
  var totalBytes = 0;
  var recoverable429Count = 0;
  var limited = false;
  Object? firstError;

  void stopAll() {
    for (final isolate in isolates) {
      isolate.kill(priority: Isolate.immediate);
    }
  }

  workerPort.listen((message) {
    final data = message as Map<dynamic, dynamic>;
    final type = data['type'] as String;
    if (type == 'progress') {
      downloads += data['downloads'] as int;
      totalBytes += data['bytes'] as int;
      recoverable429Count += data['recoverable429'] as int;
    } else if (type == 'limited') {
      limited = true;
      stopAll();
    } else if (type == 'error') {
      final statusCodeValue = data['statusCode'];
      final statusCode = statusCodeValue is int ? statusCodeValue : null;
      final workerErrorValue = data['error'];
      final workerError = workerErrorValue is String ? workerErrorValue : null;
      final malformedStatus = statusCodeValue == null || statusCode != null
          ? ''
          : ' Invalid worker status value: $statusCodeValue.';
      final workerMessage = workerError == null
          ? 'Download worker failed.$malformedStatus'
          : 'Download worker failed: $workerError$malformedStatus';
      firstError ??= StateError(
        statusCode == null
            ? workerMessage
            : 'Download bytes test failed with status $statusCode.',
      );
      stopAll();
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
        done.complete(
          _DownloadSummary(
            workers: workerCount,
            downloads: downloads,
            totalBytes: totalBytes,
            recoverable429Count: recoverable429Count,
            limited: limited,
          ),
        );
      }
    }
  });

  for (var i = 0; i < workerCount; i++) {
    active++;
    final isolate = await Isolate.spawn(
      _downloadWorkerEntry,
      <String, Object>{
        'id': i + 1,
        'archiveUrl': archiveUrl,
        'token': token,
        'limitMessage': _downloadLimitMessage,
        'sendPort': workerPort.sendPort,
      },
      onExit: exitPort.sendPort,
    );
    isolates.add(isolate);
  }

  return done.future;
}

Future<void> _downloadWorkerEntry(Map<String, Object> args) async {
  final archiveUrl = args['archiveUrl']! as String;
  final token = args['token']! as String;
  final limitMessage = args['limitMessage']! as String;
  final sendPort = args['sendPort']! as SendPort;

  const maxBackoffMs = 15000;
  var backoffMs = 250;
  var localDownloads = 0;
  var localBytes = 0;
  var localRecoverable429 = 0;
  final client = HttpClient();

  try {
    while (true) {
      final result =
          await _downloadArchive(client, archiveUrl, token, limitMessage);
      if (result.limited) {
        sendPort.send(<String, Object>{'type': 'limited'});
        return;
      }
      if (result.recoverable429) {
        localRecoverable429++;
        sendPort.send(<String, Object>{
          'type': 'progress',
          'downloads': localDownloads,
          'bytes': localBytes,
          'recoverable429': localRecoverable429,
        });
        localDownloads = 0;
        localBytes = 0;
        localRecoverable429 = 0;
        await Future<void>.delayed(Duration(milliseconds: backoffMs));
        backoffMs = (backoffMs * 2).clamp(250, maxBackoffMs);
        continue;
      }
      if (result.errorStatusCode != null) {
        sendPort.send(<String, Object>{
          'type': 'error',
          'statusCode': result.errorStatusCode!,
        });
        return;
      }

      backoffMs = 250;
      localDownloads++;
      localBytes += result.bytes;

      // if (localDownloads >= 10) {
      sendPort.send(<String, Object>{
        'type': 'progress',
        'downloads': localDownloads,
        'bytes': localBytes,
        'recoverable429': localRecoverable429,
      });
      localDownloads = 0;
      localBytes = 0;
      localRecoverable429 = 0;
      // }
    }
  } catch (error, stackTrace) {
    sendPort.send(<String, Object>{
      'type': 'error',
      'error': '$error\n$stackTrace',
    });
  } finally {
    if (localDownloads > 0 || localBytes > 0 || localRecoverable429 > 0) {
      sendPort.send(<String, Object>{
        'type': 'progress',
        'downloads': localDownloads,
        'bytes': localBytes,
        'recoverable429': localRecoverable429,
      });
    }
    client.close(force: true);
  }
}
