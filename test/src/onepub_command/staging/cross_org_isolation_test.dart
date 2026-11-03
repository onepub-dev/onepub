@Tags(['onepub_command', 'integration', 'staging'])
library;

import 'dart:io';

import 'package:onepub/src/util/one_pub_token_store.dart';
import 'package:onepub/src/util/send_command.dart';
import 'package:test/test.dart';

import 'cleanup_package.dart';
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
  required Uri expectedOrigin,
  required String token,
}) async {
  final archiveUri = Uri.parse(archiveUrl);
  if (archiveUri.scheme != expectedOrigin.scheme ||
      archiveUri.host != expectedOrigin.host ||
      archiveUri.port != expectedOrigin.port) {
    throw StateError('Archive URL left the configured staging host.');
  }
  final client = HttpClient();
  try {
    final request = await client.getUrl(archiveUri);
    request.followRedirects = false;
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
  ProvisionedTestOrganisation? alternate;
  setUpAll(() async {
    await ensureTestUsers(config);
    if (config.securityAlternateOrganisationId.trim().isEmpty) {
      alternate = await createProvisionedTestOrganisation(config, plan: 'free');
    }
  });
  tearDownAll(() async {
    if (alternate case final provisioned?) {
      await closeProvisionedTestOrganisation(config, provisioned);
    }
  });

  test('cross-organisation tokens cannot access package metadata or archive',
      () async {
    final alternateOrgId = alternate?.organisationId ??
        config.securityAlternateOrganisationId.trim();
    if (alternate == null &&
        !await hasTokenForOrganisation(config,
            organisationId: alternateOrgId)) {
      throw StateError('No token available for alternate organisation.');
    }

    await withAdmin(config, (context) async {
      final published = await publishAndVerify(context, config);
      try {
        final packagePath =
            '${context.settings.obfuscatedOrganisationId}/api/packages/${published.name}';
        final versionPath = '$packagePath/versions/${published.version}.json';
        final archiveUrl = published.versionsBody.versions
            .firstWhere((v) => v.version == published.version)
            .archiveUrl;

        Future<void> assertAlternateDenied(StagingContext _) async {
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
            expectedOrigin: Uri.parse(config.stagingUrl),
            token: alternateToken,
          );
        }

        if (alternate case final provisioned?) {
          await withScopedOrganisationToken(
            onepubUrl: provisioned.onepubUrl,
            operatorEmail: provisioned.operatorEmail,
            organisationName: provisioned.organisationName,
            organisationId: provisioned.organisationId,
            token: provisioned.onepubToken,
            action: assertAlternateDenied,
          );
        } else {
          await withMember(config, assertAlternateDenied,
              preferredOrgId: alternateOrgId);
        }
      } finally {
        await cleanupPackage(published.name);
      }
    });
  },
      timeout: const Timeout(Duration(minutes: 10)),
      skip: config.skipCrossOrgIsolation || config.skipPublish);
}
