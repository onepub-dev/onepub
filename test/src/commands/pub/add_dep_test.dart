/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'package:dcli/dcli.dart' hide equals;
import 'package:onepub/src/api/api.dart';
import 'package:onepub/src/entry_point.dart';
import 'package:onepub/src/my_runner.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:scope/scope.dart';
import 'package:test/test.dart';

import '../../test_settings.dart';
import '../test_utils.dart';

void main() {
  setUpAll(() async {
    const packageName = 'test_packag_2';
    await withTempProject(packageName, (dartProject) async {
      await withTestSettings((testSettings) async {
        final pathToOnePub = join(DartProject.self.pathToBinDir, 'onepub.dart');
        final pathToProjectRoot = dartProject.pathToProjectRoot;

        // increment the package 2 version number so we can publish it.
        final pathToPackage2Pubspec = dartProject.pathToPubSpec;
        final pubspec = PubSpec.fromFile(pathToPackage2Pubspec);
        final versions =
            await API().fetchVersions(testSettings.organisationId, packageName);
        pubspec
          ..version = Version.parse(versions.latest.version).nextMinor
          ..saveToFile(pathToPackage2Pubspec);

        // add new version to change log to stop pub publish complaining.
        join(pathToProjectRoot, 'CHANGELOG.md')
            .append('# ${pubspec.version.toString()}');

        '$pathToOnePub pub private'.start(
            workingDirectory: pathToProjectRoot,
            progress: Progress.printStdErr());
        'dart pub publish --force'.start(
            workingDirectory: pathToProjectRoot,
            progress: Progress.printStdErr());
      });
    });
  });
  test('add_dependency ...', () async {
    Settings().setVerbose(enabled: false);

    await withTempProject('test_packag_1', (dartProject) async {
      await withTestSettings((testSettings) async {
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
  });

  test('cli: entrypoint ...', () async {
    const packageName = 'test_packag_1';
    await withTempProject(packageName, (dartProject) async {
      await withTestSettings((testSettings) async {
        final size = stat(dartProject.pathToPubSpec).size;
        final scope = Scope()
          ..value(unitTestWorkingDirectoryKey, dartProject.pathToProjectRoot);
        await scope.run(() async {
          await entrypoint(
              ['pub', 'add', 'test_packag_2'], CommandSet.onepub, 'onepub');
        });
        expect(stat(dartProject.pathToPubSpec).size, greaterThan(size));
      });
    });
  }, skip: true);
}
