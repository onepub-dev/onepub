import 'dart:io';

import 'package:onepub/src/api/versions.dart';
import 'package:onepub/src/util/send_command.dart';

import '../../../test_settings.dart';

Future<PubVersionsBody> verifyPublishedPackage({
  required String packageName,
  required String version,
  required String obfuscatedOrganisationId,
}) async {
  stdout.writeln('Verifying $packageName via pub endpoint...');
  final response = await retryTestSetup(
    () => sendCommand(
      command: '$obfuscatedOrganisationId/api/packages/$packageName',
      commandType: CommandType.pub,
    ),
    (response) => response.success ? '' : response.errorMessage,
  );

  if (!response.success) {
    throw StateError('Package verification failed: ${response.errorMessage}');
  }

  final envelope = response.parsePub(PubVersionsBody.fromJson);
  final body = envelope.body;
  if (body == null) {
    throw StateError('Package verification returned no data.');
  }

  if (body.name != packageName) {
    throw StateError('''
Package verification mismatch: expected $packageName, got ${body.name}.''');
  }

  final hasVersion = body.versions.any((entry) => entry.version == version);
  if (!hasVersion) {
    throw StateError('Package version $version not found in pub response.');
  }

  return body;
}
