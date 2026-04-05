import 'dart:async';
import 'dart:io';

import 'package:dcli/dcli.dart';
import 'package:dcli_core/dcli_core.dart' as core;
import 'package:path/path.dart';

Future<void> pubGetTestPackage(
    String packageName, String version, String apiUrl) async {
  stdout.writeln('Running dart pub get for $packageName $version...');

  await core.withTempDirAsync((tempDir) async {
    File(join(tempDir, 'pubspec.yaml')).writeAsStringSync('''
name: onepub_staging_consumer
description: OnePub staging pub get test package.
version: 0.0.1
environment:
  sdk: '>=3.5.0 <4.0.0'
dependencies:
  $packageName:
    hosted: $apiUrl
    version: $version
''');

    final progress = Progress.capture();
    'dart pub get'
        .start(workingDirectory: tempDir, progress: progress, nothrow: true);
    stdout.writeln(progress.toParagraph());
    if (progress.exitCode != 0) {
      throw StateError(
          'dart pub get failed with exit code ${progress.exitCode}');
    }
  });
}
