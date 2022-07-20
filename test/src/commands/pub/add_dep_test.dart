/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'package:dcli/dcli.dart' hide equals;
import 'package:onepub/src/entry_point.dart';
import 'package:onepub/src/my_runner.dart';
import 'package:scope/scope.dart';
import 'package:test/test.dart';

import '../test_utils.dart';

void main() {
  setUpAll(() {
    // publish the test_packag_2 so we can depend on it.
    final pathToTestPackage2 =
        join(DartProject.self.pathToTestDir, 'fixtures', 'test_packag_2');
    final pathToOnePub = join(DartProject.self.pathToBinDir, 'onepub.dart');

    // increment the package 2 version number so we can publish it.
    final pathToPackage2Pubspec = join(pathToTestPackage2, 'pubspec.yaml');
    final pubspec = PubSpec.fromFile(pathToPackage2Pubspec);
    final version = pubspec.version!;
    pubspec
      ..version = version.nextMinor
      ..saveToFile(pathToPackage2Pubspec);

    // add new version to change log to stop pub publish complaining.
    join(pathToTestPackage2, 'CHANGELOG.md')
        .append('# ${pubspec.version.toString()}');

    '$pathToOnePub pub private'.start(
        workingDirectory: pathToTestPackage2, progress: Progress.printStdErr());
    'dart pub publish --force'.start(
        workingDirectory: pathToTestPackage2, progress: Progress.printStdErr());
  });
  test('add_dependency ...', () async {
    Settings().setVerbose(enabled: false);

    withTempProject('test_packag_1', (dartProject) {
      var pubSpec = dartProject.pubSpec;
      expect(pubSpec.dependencies.containsKey('test_packag_2'), isFalse);

      // run onepub add <dep>
      final progress = 'dart $pathToOnePubScript pub add test_packag_2'
          .start(workingDirectory: dartProject.pathToProjectRoot);
      expect(progress.exitCode, equals(0));

      // load the updated pubspec
      pubSpec = PubSpec.fromFile(dartProject.pathToPubSpec);
      expect(pubSpec.dependencies.containsKey('test_packag_2'), isTrue);
    });
  });

  test('cli: entrypoint ...', () async {
    const packageName = 'test_packag_1';
    withTempProject(packageName, (dartProject) {
      final size = stat(dartProject.pathToPubSpec).size;
      Scope()
        ..value(unitTestWorkingDirectoryKey, dartProject.pathToProjectRoot)
        ..run(() {
          waitForEx(entrypoint(
              ['pub', 'add', 'test_packag_2'], CommandSet.onepub, 'onepub'));
        });
      expect(stat(dartProject.pathToPubSpec).size, greaterThan(size));
    });
  }, skip: true);
}
