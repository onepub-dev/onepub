@Tags(['onepub_command', 'integration'])
library;
/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'dart:io';

import 'package:dcli/dcli.dart';
import 'package:onepub/src/api/api.dart';
import 'package:onepub/src/entry_point.dart';
import 'package:onepub/src/exceptions.dart';
import 'package:onepub/src/util/send_command.dart';
import 'package:path/path.dart' hide equals;
import 'package:pub_semver/pub_semver.dart' as ps;
import 'package:pubspec_manager/pubspec_manager.dart';
import 'package:scope/scope.dart';
import 'package:test/test.dart';

import '../../../../impersonate_user.dart';
import '../../../../test_users.dart';
import '../test_utils.dart';

late final String dependencyPackageName;

void main() {
  setUpAll(() async {
    const fixtureName = 'test_packag_2';
    dependencyPackageName =
        'onepub_test_package_2_${DateTime.now().microsecondsSinceEpoch}_$pid';
    await TestUsers(init: true).init();
    await withTempProject(fixtureName, (dartProject) async {
      // await withTestSettings((testSettings) async {
      final member = TestUsers().administrator;
      await _ensurePackageExists(dependencyPackageName);
      await impersonateMember(
          member: member,
          action: () async {
            final pathToOnePub =
                join(DartProject.self.pathToBinDir, 'onepub.dart');
            final pathToProjectRoot = dartProject.pathToProjectRoot;

            // increment the package 2 version number so we can publish it.
            final pathToPackage2Pubspec = dartProject.pathToPubSpec;
            final pubspec = PubSpec.loadFromPath(pathToPackage2Pubspec);

            final next = await _nextPublishVersion(
              member.obfuscatedOrganisationId,
              dependencyPackageName,
              pubspec,
            );

            pubspec
              ..name.set(dependencyPackageName)
              ..version.set(next.canonicalizedVersion)
              ..saveTo(pathToPackage2Pubspec);

            // add new version to change log to stop pub publish complaining.
            join(pathToProjectRoot, 'CHANGELOG.md')
                .append('# ${pubspec.version}');

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
      // await withTestSettings((testSettings) async {
      final member = TestUsers().administrator;
      await impersonateMember(
          member: member,
          action: () async {
            var pubSpec = dartProject.pubSpec;
            expect(pubSpec.dependencies.exists(dependencyPackageName), isFalse);

            // run onepub add <dep>
            final progress =
                'dart $pathToOnePubScript pub add $dependencyPackageName'
                    .start(workingDirectory: dartProject.pathToProjectRoot);
            expect(progress.exitCode, equals(0));

            // load the updated pubspec
            pubSpec = PubSpec.loadFromPath(dartProject.pathToPubSpec);
            expect(pubSpec.dependencies.exists(dependencyPackageName), isTrue);
          });
    });
  });

  test('cli: entrypoint ...', () async {
    const packageName = 'test_packag_1';
    await withTempProject(packageName, (dartProject) async {
      /// await withTestSettings((testSettings) async {
      final member = TestUsers().administrator;
      await impersonateMember(
          member: member,
          action: () async {
            final size = stat(dartProject.pathToPubSpec).size;
            final scope = Scope()
              ..value(
                  unitTestWorkingDirectoryKey, dartProject.pathToProjectRoot);
            await scope.run(() async {
              await entrypoint(
                  args: ['pub', 'add', dependencyPackageName],
                  executableName: 'onepub');
            });
            expect(stat(dartProject.pathToPubSpec).size, greaterThan(size));
          });
    });
  }, skip: true);
}

Future<void> _ensurePackageExists(String packageName) async {
  final response = await sendCommand(
    command: 'test/package/create/$packageName?team=everyone',
    commandType: CommandType.cli,
    method: Method.post,
  );
  if (!response.success && response.status != HttpStatus.conflict) {
    throw StateError(
      'Unable to create package $packageName (HTTP ${response.status}): '
      '${response.errorMessage}',
    );
  }
}

Future<ps.Version> _nextPublishVersion(
  String organisationId,
  String packageName,
  PubSpec pubspec,
) async {
  try {
    final versions = await API().fetchVersions(organisationId, packageName);
    final latestVersion = versions.latest.version.trim();
    if (latestVersion.isEmpty) {
      return pubspec.version.semVersion;
    }
    return ps.Version.parse(latestVersion).nextMinor;
  } on APIException catch (e) {
    if (!e.message.toLowerCase().contains('unknown package name')) {
      rethrow;
    }
    return pubspec.version.semVersion;
  }
}
