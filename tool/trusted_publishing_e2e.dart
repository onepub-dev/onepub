import 'dart:convert';
import 'dart:io';

import 'package:onepub/src/api/api.dart';
import 'package:onepub/src/onepub_settings.dart';
import 'package:onepub/src/util/one_pub_token_store.dart';
import 'package:path/path.dart' as p;

import '../test/test_settings.dart';

/// Runs only inside the build-machine GitHub runner job. The bootstrap token
/// stays in op-build; this process has only the GitHub workload identity.
Future<void> main() async {
  Directory? temp;
  try {
    final environment = Platform.environment;
    final target = assertSafeOnePubTestUrl(environment['ONEPUB_E2E_URL'] ?? '',
        source: 'GitHub trusted publishing');
    if (Uri.parse(target).host != '127.0.0.1') {
      throw StateError(
          'This workflow requires the build-machine loopback stack.');
    }
    final package = environment['ONEPUB_E2E_PACKAGE'] ?? '';
    if (!RegExp(r'^onepub_test_trusted_[a-f0-9]+$').hasMatch(package)) {
      throw StateError('Invalid isolated test package name.');
    }
    final expectedVersion = environment['ONEPUB_E2E_VERSION'] ?? '';
    final audience = environment['ONEPUB_E2E_AUDIENCE'] ?? '';
    final settingsPath = environment[OnePubSettings.onepubPathEnvKey];
    if (settingsPath == null || audience.isEmpty || expectedVersion.isEmpty) {
      throw StateError('Missing workflow test configuration.');
    }
    final cli = p.absolute('bin', 'onepub.dart');
    await OnePubSettings.withPathTo(settingsPath, () async {
      final settings = OnePubSettings.use()..onepubUrl = target;
      await settings.save();
      final status = await API().status().timeout(const Duration(seconds: 15));
      if (status.version.toString() != expectedVersion) {
        throw StateError(
            'Expected server $expectedVersion; got ${status.version}.');
      }
      await runDart(
          [cli, 'login', 'trusted', '--publish-only', '--audience', audience]);
      final credentials = (await OnePubTokenStore().credentials).toList();
      if (credentials.length != 1) {
        throw StateError('Expected one newly installed publishing credential.');
      }
      final hosted = credentials.single.url.toString();
      assertSafeOnePubTestUrl(hosted, source: 'trusted exchange hosted URL');
      if (Uri.parse(hosted).origin != Uri.parse(target).origin) {
        throw StateError('Exchange returned a different server origin.');
      }
      temp = Directory.systemTemp.createTempSync('onepub-trusted-package-');
      final directory = temp!.path;
      File(p.join(directory, 'pubspec.yaml')).writeAsStringSync('''
name: $package
version: 1.0.0
description: Isolated OnePub trusted publishing integration test package.
publish_to: ${jsonEncode(hosted)}
environment:
  sdk: '>=3.5.0 <4.0.0'
''');
      Directory(p.join(directory, 'lib')).createSync();
      File(p.join(directory, 'lib', '$package.dart'))
          .writeAsStringSync("const message = 'trusted publishing works';\n");
      File(p.join(directory, 'README.md'))
          .writeAsStringSync('# Integration test\n');
      File(p.join(directory, 'CHANGELOG.md'))
          .writeAsStringSync('# 1.0.0\nTest release.\n');
      File(p.join(directory, 'LICENSE'))
          .writeAsStringSync('Test fixture. All rights reserved.\n');
      await runDart(['pub', 'publish', '--force'], workingDirectory: directory);
      stdout.writeln(
          'Published $package 1.0.0 using the GitHub workload identity.');
    });
  } on Object catch (e) {
    stderr.writeln('Trusted publishing E2E failed: $e');
    exitCode = 1;
  } finally {
    temp?.deleteSync(recursive: true);
  }
}

Future<void> runDart(List<String> args, {String? workingDirectory}) async {
  final process = await Process.start(Platform.resolvedExecutable, args,
      workingDirectory: workingDirectory, mode: ProcessStartMode.inheritStdio);
  try {
    final code = await process.exitCode.timeout(const Duration(minutes: 5));
    if (code != 0) {
      throw StateError('Dart command failed with exit code $code.');
    }
  } on Object {
    process.kill();
    rethrow;
  }
}
