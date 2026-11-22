#! /usr/bin/env dcli

// Test-only entrypoint. The shipped bin/onepub.dart has no simulator override.
import 'dart:io';

import 'package:dcli/dcli.dart';
import 'package:onepub/src/device/device_key.dart';
import 'package:onepub/src/device/device_session.dart';
import 'package:onepub/src/entry_point.dart';
import 'package:onepub/src/onepub_settings.dart';

import '../test/test_settings.dart';

Future<void> main(List<String> arguments) async {
  final tcti = env['ONEPUB_TEST_TPM_TCTI'];
  if (!Platform.isLinux ||
      tcti == null ||
      tcti.isEmpty ||
      (env['ONEPUB_PATH'] ?? '').isEmpty) {
    throw StateError('The test CLI requires Linux, ONEPUB_TEST_TPM_TCTI '
        'and an isolated ONEPUB_PATH.');
  }
  final settingsArgument = arguments.indexOf('--settings');
  final settingsFile = settingsArgument < 0
      ? OnePubSettings.defaultPathToSettings
      : arguments[settingsArgument + 1];
  if (!File(settingsFile).existsSync()) {
    throw StateError('Prepare isolated test settings before invoking the CLI.');
  }
  final settings = OnePubSettings(pathToSettings: settingsFile);
  assertSafeOnePubTestUrl(settings.onepubWebUrl, source: 'test device CLI');
  for (final repository in (await DeviceSession.readRegistry(settings)).keys) {
    assertSafeOnePubTestUrl(repository, source: 'test device CLI registry');
  }
  await DeviceKey.withLinuxBackendForTesting(
      LinuxTpmBackend.forTesting(
          tcti: tcti,
          toolsDirectory: env['ONEPUB_TEST_TPM_TOOLS'] ?? '/usr/bin'),
      () => entrypoint(args: arguments, executableName: 'onepub-test'));
}
