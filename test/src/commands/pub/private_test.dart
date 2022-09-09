/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'package:dcli/dcli.dart' hide equals;
import 'package:onepub/src/entry_point.dart';
import 'package:onepub/src/my_runner.dart';
import 'package:onepub/src/onepub_settings.dart';
import 'package:onepub/src/version/version.g.dart';
import 'package:scope/scope.dart';
import 'package:test/test.dart';
import 'package:url_builder/url_builder.dart';

import '../../test_settings.dart';
import '../test_utils.dart';

void main() {
  test('cli: private ...', () async {
    const packageName = 'test_packag_1';

    withTempProject(packageName, (dartProject) {
      withTestSettings((testSettings) async {
        final settings = OnePubSettings.use;
        final organisationName = settings.organisationName;
        expect(dartProject.pubSpec.pubspec.publishTo, isNull);

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
                'See ${urlJoin(OnePubSettings.use.onepubWebUrl, 'publish')}'),
            isTrue);

        final pubSpec = PubSpec.fromFile(dartProject.pathToPubSpec);
        expect(
            pubSpec.pubspec.publishTo.toString(),
            equals(
                '${urlJoin(settings.onepubApiUrl, settings.obfuscatedOrganisationId)}/'));

        expect(stat(dartProject.pathToPubSpec).size, greaterThan(size));
      });
    });
  });

  test('cli: entrypoint ...', () async {
    const packageName = 'test_packag_1';
    withTempProject(packageName, (dartProject) {
      withTestSettings((testSettings) async {
        final size = stat(dartProject.pathToPubSpec).size;
        Scope()
          ..value(unitTestWorkingDirectoryKey, dartProject.pathToProjectRoot)
          ..run(() {
            waitForEx(
                entrypoint(['pub', 'private'], CommandSet.onepub, 'onepub'));
          });
        expect(stat(dartProject.pathToPubSpec).size, greaterThan(size));
      });
    });
  });
}
