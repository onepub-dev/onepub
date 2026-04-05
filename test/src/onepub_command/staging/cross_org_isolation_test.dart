@Tags(['onepub_command', 'integration', 'staging'])
library;

import 'dart:io';

import 'package:onepub/src/util/one_pub_token_store.dart';
import 'package:onepub/src/util/send_command.dart';
import 'package:test/test.dart';

import 'staging_common.dart';

Future<void> _expectCrossOrgDenied(
  EndpointResponse response,
  String action,
) async {
  if (response.success) {
    throw StateError(
        'Cross-org isolation failed: $action unexpectedly succeeded.');
  }
  if (response.status != HttpStatus.unauthorized &&
      response.status != HttpStatus.forbidden &&
      response.status != HttpStatus.notFound) {
    throw StateError(
      'Cross-org isolation failed: expected 401/403/404 for $action, '
      'got ${response.status}.',
    );
  }
}

Future<void> _expectCrossOrgArchiveDenied({
  required String archiveUrl,
  required String token,
}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(archiveUrl));
    request.headers.set('authorization', token);
    final response = await request.close();
    await response.drain<void>();
    if (response.statusCode != HttpStatus.unauthorized &&
        response.statusCode != HttpStatus.forbidden &&
        response.statusCode != HttpStatus.notFound) {
      throw StateError(
        'Cross-org isolation failed: expected 401/403/404 for archive '
        'request, got ${response.statusCode}.',
      );
    }
  } finally {
    client.close(force: true);
  }
}

void main() {
  final config = StagingConfig.fromEnv();
  setUpAll(() => ensureTestUsers(config));

  test('cross-organisation tokens cannot access package metadata or archive',
      () async {
    final alternateOrgId = config.securityAlternateOrganisationId.trim();
    if (alternateOrgId.isEmpty) {
      stdout.writeln(
        'Skipping cross-org isolation test: set ONEPUB_SECURITY_ALT_ORG_ID '
        'to an alternate organisation id.',
      );
      return;
    }

    final hasAlternateAccess = await hasTokenForOrganisation(
      config,
      organisationId: alternateOrgId,
    );
    if (!hasAlternateAccess) {
      stdout.writeln(
        'Skipping cross-org isolation test: no token available for '
        'organisation $alternateOrgId.',
      );
      return;
    }

    await withAdmin(config, (context) async {
      final published = await publishAndVerify(context, config);
      final packagePath =
          '${context.settings.obfuscatedOrganisationId}/api/packages/${published.name}';
      final versionPath = '$packagePath/versions/${published.version}.json';
      final archiveUrl = published.versionsBody.versions
          .firstWhere((v) => v.version == published.version)
          .archiveUrl;

      await withMember(
        config,
        (_) async {
          final alternateToken = await OnePubTokenStore().load();
          await _expectCrossOrgDenied(
            await sendCommand(
              command: packagePath,
              commandType: CommandType.pub,
            ),
            'cross-org metadata request',
          );
          await _expectCrossOrgDenied(
            await sendCommand(
              command: versionPath,
              commandType: CommandType.pub,
            ),
            'cross-org version request',
          );
          await _expectCrossOrgArchiveDenied(
            archiveUrl: archiveUrl,
            token: alternateToken,
          );
        },
        preferredOrgId: alternateOrgId,
      );
    });
  },
      timeout: const Timeout(Duration(minutes: 10)),
      skip: config.skipCrossOrgIsolation || config.skipPublish);
}
