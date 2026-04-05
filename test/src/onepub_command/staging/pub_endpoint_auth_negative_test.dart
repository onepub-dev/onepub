@Tags(['onepub_command', 'integration', 'staging'])
library;

import 'dart:io';

import 'package:onepub/src/util/send_command.dart';
import 'package:test/test.dart';

import 'staging_common.dart';

Future<void> _expectDenied(EndpointResponse response, String action) async {
  if (response.success) {
    throw StateError('Security test failed: $action unexpectedly succeeded.');
  }
  if (response.status != HttpStatus.unauthorized &&
      response.status != HttpStatus.forbidden) {
    throw StateError(
      'Security test failed: expected 401/403 for $action, '
      'got ${response.status}.',
    );
  }
}

Future<void> _expectArchiveDenied({
  required String archiveUrl,
  required String? authorization,
  required String action,
}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(archiveUrl));
    if (authorization != null) {
      request.headers.set('authorization', authorization);
    }
    final response = await request.close();
    await response.drain<void>();
    if (response.statusCode != HttpStatus.unauthorized &&
        response.statusCode != HttpStatus.forbidden) {
      throw StateError(
        'Security test failed: expected 401/403 for $action, '
        'got ${response.statusCode}.',
      );
    }
  } finally {
    client.close(force: true);
  }
}

void main() {
  final config = StagingConfig.fromEnv();
  setUpAll(() => ensureTestUsers(config));

  test('pub endpoints deny anonymous access', () async {
    await withAdmin(config, (context) async {
      final published = await publishAndVerify(context, config);
      final packagePath =
          '${context.settings.obfuscatedOrganisationId}/api/packages/${published.name}';
      final versionPath = '$packagePath/versions/${published.version}.json';
      final archiveUrl = published.versionsBody.versions
          .firstWhere((v) => v.version == published.version)
          .archiveUrl;

      await _expectDenied(
        await sendCommand(
          command: packagePath,
          commandType: CommandType.pub,
          authorised: false,
        ),
        'anonymous metadata request',
      );
      await _expectDenied(
        await sendCommand(
          command: versionPath,
          commandType: CommandType.pub,
          authorised: false,
        ),
        'anonymous version request',
      );
      await _expectArchiveDenied(
        archiveUrl: archiveUrl,
        authorization: null,
        action: 'anonymous archive request',
      );
    });
  },
      timeout: const Timeout(Duration(minutes: 10)),
      skip: config.skipUnauthorizedTest || config.skipPublish);

  test('pub endpoints deny invalid tokens', () async {
    await withAdmin(config, (context) async {
      final published = await publishAndVerify(context, config);
      final packagePath =
          '${context.settings.obfuscatedOrganisationId}/api/packages/${published.name}';
      final versionPath = '$packagePath/versions/${published.version}.json';
      final archiveUrl = published.versionsBody.versions
          .firstWhere((v) => v.version == published.version)
          .archiveUrl;
      const invalidToken = 'invalid-token';

      await _expectDenied(
        await sendCommand(
          command: packagePath,
          commandType: CommandType.pub,
          authorised: false,
          headers: const <String, String>{'authorization': invalidToken},
        ),
        'invalid-token metadata request',
      );
      await _expectDenied(
        await sendCommand(
          command: versionPath,
          commandType: CommandType.pub,
          authorised: false,
          headers: const <String, String>{'authorization': invalidToken},
        ),
        'invalid-token version request',
      );
      await _expectArchiveDenied(
        archiveUrl: archiveUrl,
        authorization: invalidToken,
        action: 'invalid-token archive request',
      );
    });
  },
      timeout: const Timeout(Duration(minutes: 10)),
      skip: config.skipInvalidTokenTest || config.skipPublish);
}
