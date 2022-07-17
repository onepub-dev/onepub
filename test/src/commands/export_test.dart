/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'package:onepub/src/onepub_settings.dart';
import 'package:onepub/src/version/version.g.dart';
import 'package:path/path.dart' hide equals;
import 'package:settings_yaml/settings_yaml.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  test('onepub export env...', () async {
    final clean = runCmd('export');

    final settings = OnePubSettings.load();
    final organisationName = settings.organisationName;

    final first = clean.first;
    expect(first, 'OnePub version: $packageVersion ');

    expect(clean.contains('Exporting OnePub token for $organisationName.'),
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
  });

  test('onepub export CI/CD...', () async {
    final settings =
        SettingsYaml.load(pathToSettings: join('test', 'test_settings.yaml'));

    final cicdUser = settings.asString('cicd_member');
    final clean = runCmd('export --user $cicdUser');

    final onepubSettings = OnePubSettings.load();
    final organisationName = onepubSettings.organisationName;

    final first = clean.first;
    expect(first, 'OnePub version: $packageVersion ');

    expect(clean.contains('Exporting OnePub token for $organisationName.'),
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
  });
}
