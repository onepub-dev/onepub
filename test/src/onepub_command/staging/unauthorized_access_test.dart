@Tags(['onepub_command', 'integration', 'staging'])
library;

import 'dart:io';

import 'package:onepub/src/util/send_command.dart';
import 'package:test/test.dart';

import 'staging_common.dart';

Future<void> unauthorizedAccessTest(String command) async {
  stdout.writeln('Testing unauthorized access to $command...');
  final response = await sendCommand(
    command: command,
    commandType: CommandType.cli,
    authorised: false,
  );

  if (response.success) {
    throw StateError(
        'Unauthorized test failed: request unexpectedly succeeded.');
  }

  if (response.status != 401 && response.status != 403) {
    throw StateError(
        'Unauthorized test failed: expected 401/403, got ${response.status}.');
  }
}

void main() {
  final config = StagingConfig.fromEnv();
  setUpAll(() => ensureTestUsers(config));

  test('unauthorized access', () async {
    await withAdmin(config, (context) async {
      await unauthorizedAccessTest('organisation/details');
    });
  },
      timeout: const Timeout(Duration(minutes: 5)),
      skip: config.skipUnauthorizedTest);
}
