/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'package:dcli_core/dcli_core.dart';
import 'package:onepub/src/entry_point.dart';
import 'package:onepub/src/onepub_settings.dart';
import 'package:onepub/src/version/version.g.dart';
import 'package:pubspec_manager/pubspec_manager.dart';
import 'package:scope/scope.dart';
import 'package:test/test.dart';

import '../../../impersonate_user.dart';
import '../../../test_users.dart';
import '../test_utils.dart';

void main() {
  setUpAll(() async {
    await TestUsers(init: true).init();
  });
  test('cli: private ...', () async {
    const packageName = 'test_packag_1';

    await withTempProject(packageName, (dartProject) async {
      // await withTestSettings((testSettings) async {
      final member = TestUsers().administrator;
      await impersonateMember(
          member: member,
          action: () async {
            final settings = OnePubSettings.use();
            final organisationName = settings.organisationName;
            expect(dartProject.pubSpec.publishTo, isNull);

            final size = stat(dartProject.pathToPubSpec).size;

            // run onepub private
            final clean = runCmd('pub private',
                workingDirectory: dartProject.pathToProjectRoot);
            final first = clean.first;
            expect(first, 'OnePub version: $packageVersion ');

            expect(
                clean.contains(
                    '$packageName has been marked as a private package for the '
                    'organisation $organisationName.'),
                isTrue);

            expect(
                clean.contains(
                    "Run 'dart/flutter pub publish' to publish $packageName to OnePub"),
                isTrue);
            expect(
                clean.contains(
                    'See ${OnePubSettings.use().guidePublishOnePubUrl}'),
                isTrue);

            final pubSpec = PubSpec.loadFromPath(dartProject.pathToPubSpec);
            expect(pubSpec.publishTo.toString(),
                equals(settings.onepubApiUrlAsString));

            expect(stat(dartProject.pathToPubSpec).size, greaterThan(size));
          });
    });
  });

  test('cli: entrypoint ...', () async {
    const packageName = 'test_packag_1';
    await withTempProject(packageName, (dartProject) async {
      // await withTestSettings((testSettings) async {
      final member = TestUsers().administrator;
      await impersonateMember(
          member: member,
          action: () async {
            final size = stat(dartProject.pathToPubSpec).size;
            final scope = Scope()
              ..value(
                  unitTestWorkingDirectoryKey, dartProject.pathToProjectRoot);
            await scope.run(() async {
              await entrypoint(['pub', 'private'], 'onepub');
              expect(stat(dartProject.pathToPubSpec).size, greaterThan(size));
            });
          });
    });
  });
}
