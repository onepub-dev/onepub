/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'package:dcli/dcli.dart' hide equals;
import 'package:onepub/src/onepub_settings.dart';
import 'package:onepub/src/version/version.g.dart';
import 'package:test/test.dart';
import 'package:url_builder/url_builder.dart';

import 'cmd_runner.dart';

void main() {
  test('private ...', () async {
    var pathToRoot = DartProject.self.pathToProjectRoot;
    var settings = OnePubSettings.load();
    final organisationName = settings.organisationName;

    withTempDir((workingDir) {
      final packageName = 'test_packag_1';
      copyTree(join(pathToRoot, 'test', 'fixtures', packageName), workingDir);

      var pathToPubSpec = join(workingDir, 'pubspec.yaml');
      var pubSpec = PubSpec.fromFile(pathToPubSpec);
      expect(pubSpec.pubspec.publishTo, isNull);

      // run onepub private
      var clean = runCmd('private', workingDirectory: workingDir);
      var first = clean.first;
      expect(first, 'OnePub version: $packageVersion ');

      expect(
          clean.contains(
              '$packageName has been marked as a private package for the organisation $organisationName.'),
          isTrue);

      expect(
          clean.contains(
              "Run 'dart/flutter pub publish' to publish $packageName to OnePub"),
          isTrue);
      expect(
          clean.contains(
              'See ${urlJoin(OnePubSettings().onepubWebUrl, 'publish')}'),
          isTrue);

      pubSpec = PubSpec.fromFile(pathToPubSpec);
      expect(
          pubSpec.pubspec.publishTo.toString(),
          equals(
              '${urlJoin(settings.onepubApiUrl, settings.obfuscatedOrganisationId)}/'));
    });
  });
}
