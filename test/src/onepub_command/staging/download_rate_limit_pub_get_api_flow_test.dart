@Tags(['onepub_command', 'integration', 'staging'])
library;

import 'dart:async';
import 'dart:io';

import 'package:onepub/src/util/one_pub_token_store.dart';
import 'package:onepub/src/util/send_command.dart';
import 'package:test/test.dart';

import 'staging_common.dart';

class DownloadLimitResult {
  final Map<int, int> metadataStatuses;
  final Map<int, int> versionStatuses;
  final Map<int, int> archiveStatuses;

  DownloadLimitResult({
    required this.metadataStatuses,
    required this.versionStatuses,
    required this.archiveStatuses,
  });

  int _statusCount(Map<int, int> source, int status) => source[status] ?? 0;

  int get metadataLimited => _statusCount(metadataStatuses, 429);
  int get versionLimited => _statusCount(versionStatuses, 429);
  int get archiveLimited => _statusCount(archiveStatuses, 429);
  int get totalLimited => metadataLimited + versionLimited + archiveLimited;
}

Future<DownloadLimitResult> simulatePubGetApiFlow({
  required StagingContext context,
  required PublishedPackage published,
  required int requests,
}) async {
  final packagePath =
      '${context.settings.obfuscatedOrganisationId}/api/packages/${published.name}';
  final versionPath = '$packagePath/versions/${published.version}.json';

  final metadataStatuses = <int, int>{};
  final versionStatuses = <int, int>{};
  final archiveStatuses = <int, int>{};

  final token = await OnePubTokenStore().load();
  final archiveUrl = published.versionsBody.versions
      .firstWhere((v) => v.version == published.version)
      .archiveUrl;

  final results = await Future.wait(List.generate(requests, (_) async {
    final metadata = await sendCommand(
      command: packagePath,
      commandType: CommandType.pub,
    );

    final version = await sendCommand(
      command: versionPath,
      commandType: CommandType.pub,
    );

    final archiveStatus = await _downloadArchiveStatus(archiveUrl, token);
    return (
      metadataStatus: metadata.status,
      versionStatus: version.status,
      archiveStatus: archiveStatus,
    );
  }));

  for (final result in results) {
    metadataStatuses[result.metadataStatus] =
        (metadataStatuses[result.metadataStatus] ?? 0) + 1;
    versionStatuses[result.versionStatus] =
        (versionStatuses[result.versionStatus] ?? 0) + 1;
    archiveStatuses[result.archiveStatus] =
        (archiveStatuses[result.archiveStatus] ?? 0) + 1;
  }

  stdout
    ..writeln('Download-limit pub flow metadata statuses: $metadataStatuses')
    ..writeln('Download-limit pub flow version statuses: $versionStatuses')
    ..writeln('Download-limit pub flow archive statuses: $archiveStatuses');

  return DownloadLimitResult(
    metadataStatuses: metadataStatuses,
    versionStatuses: versionStatuses,
    archiveStatuses: archiveStatuses,
  );
}

Future<int> _downloadArchiveStatus(String archiveUrl, String token) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(archiveUrl));
    request.headers.set('authorization', token);
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

void main() {
  final config = StagingConfig.fromEnv();
  setUpAll(() => ensureTestUsers(config));

  test('download rate limits: pub get API flow', () async {
    await withSuiteAdministrator(config, (context) async {
      final published = await publishAndVerify(context, config);
      final result = await simulatePubGetApiFlow(
        context: context,
        published: published,
        requests: config.downloadLimitRequests,
      );

      if (result.totalLimited == 0) {
        throw StateError(
          'Download-limit test did not produce any 429 responses. '
          'Increase ONEPUB_DOWNLOAD_LIMIT_REQUESTS.',
        );
      }
    });
  },
      timeout: const Timeout(Duration(minutes: 15)),
      skip: config.skipDownloadLimit || config.skipPublish);
}
