@Tags(['onepub_command', 'integration', 'staging'])
library;

import 'dart:io';

import 'package:onepub/src/util/send_command.dart';
import 'package:test/test.dart';

import 'staging_common.dart';

Future<void> invalidTokenTest(String command) async {
  stdout.writeln('Testing invalid token against $command...');
  final response = await sendCommand(
    command: command,
    commandType: CommandType.cli,
    authorised: false,
    headers: const <String, String>{'authorization': 'invalid-token'},
  );

  if (response.success) {
    throw StateError(
        'Invalid token test failed: request unexpectedly succeeded.');
  }

  if (response.status != 401 && response.status != 403) {
    throw StateError(
        'Invalid token test failed: expected 401/403, got ${response.status}.');
  }
}

void main() {
  final config = StagingConfig.fromEnv();
  setUpAll(() => ensureTestUsers(config));

  test('invalid token', () async {
    await withAdmin(config, (context) async {
      await invalidTokenTest('organisation/details');
    });
  },
      timeout: const Timeout(Duration(minutes: 5)),
      skip: config.skipInvalidTokenTest);
}
