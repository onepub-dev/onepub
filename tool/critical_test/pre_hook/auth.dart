#! /usr/bin/env dcli

import 'dart:io';
import 'package:dcli/dcli.dart';
import '../local_server.dart';

/// Check the guarded test target and its isolated System Administrator token.
/// Never use the operator's normal OnePub settings or publishing credentials.
Future<void> main(List<String> args) async {
  await startLocalServer();
  final result = await Process.run(Platform.resolvedExecutable,
      ['run', 'tool/check_system_test_prereqs.dart']);
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  if (result.exitCode != 0) {
    await stopLocalServer();
    exitCode = result.exitCode;
  } else {
    print(green('Local Docker test server is ready.'));
  }
}
