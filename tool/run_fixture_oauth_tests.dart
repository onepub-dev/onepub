#! /usr/bin/env dcli

import 'dart:convert';
import 'dart:io';

import 'package:dcli/dcli.dart' show DartSdk, env;

import '../test/fixture_oauth.dart';

/// Own rotating fixture grants in this parent process, forwarding the test
/// arguments and reporter streams unchanged to independent Dart test isolates.
Future<void> main(List<String> args) async {
  FixtureOAuthBroker? broker;
  try {
    final authorization = jsonDecode(env[FixtureOAuth.authorizationKey] ?? '')
        as Map<String, dynamic>;
    broker = await FixtureOAuth.startHarness(
        authorization['onepubUrl'] as String,
        authorization: authorization);
    final process = await Process.start(
      DartSdk().pathToDartExe!,
      ['test', ...args],
      environment: broker.workerEnvironment(Platform.environment),
      includeParentEnvironment: false,
      mode: ProcessStartMode.inheritStdio,
    );
    exitCode = await process.exitCode;
  } on Object {
    // Configuration and transport exceptions must never disclose seed JSON.
    stderr.writeln('Fixture OAuth test harness failed.');
    exitCode = 1;
  } finally {
    await broker?.close();
  }
}
