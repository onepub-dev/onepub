/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'package:dcli/dcli.dart' hide equals;
import 'package:onepub/src/onepub_paths.dart';
import 'package:onepub/src/onepub_settings.dart';
import 'package:onepub/src/version/version.g.dart';
import 'package:scope/scope.dart';
import 'package:test/test.dart';

import '../test_settings.dart';
import 'test_utils.dart';

void main() {
  test('onepub import --file', () async {
    final testSettings = TestSettings();

    withTempDir((pathToOnePubSettings) {
      Scope()
        ..value(scopeKeyPathToSettings, pathToOnePubSettings)
        ..run(() {
          final onepubToken = testSettings.onepubToken;
          final settings = OnePubSettings.load();
          final organisationName = settings.organisationName;

          try {
            'onepub.token.yaml'.write('''
# SettingsYaml settings file
onepubToken: "$onepubToken"
''');
            runCmd('export --file ');
            final clean = runCmd('import --file ');

            final first = clean.first;
            expect(first, 'OnePub version: $packageVersion ');

            expect(
                clean.contains('Exporting OnePub token for $organisationName.'),
                isTrue);

            expect(
                clean.contains(
                    'Add the following environment variable to your CI/CD secrets.'),
                isTrue);

            final last = clean[(clean.length - 2)];
            expect(last.startsWith('ONEPUB_SECRET='), isTrue);

            // check the secret has a guid
            final parts = last.split('=');
            expect(parts.length, equals(2));
            expect(parts[1].length, equals(36));
          } on DCliException {}
        });
    });
  });
}
