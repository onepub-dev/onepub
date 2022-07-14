/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'package:onepub/src/onepub_settings.dart';
import 'package:onepub/src/version/version.g.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  test('onepub import --file', () async {
    runCmd('export --file ');
    var clean = runCmd('import --file ');

    var settings = OnePubSettings.load();
    final organisationName = settings.organisationName;


    var first = clean.first;
    expect(first, 'OnePub version: $packageVersion ');

    expect(clean.contains('Exporting OnePub token for $organisationName.'),
        isTrue);

    expect(
        clean.contains(
            'Add the following environment variable to your CI/CD secrets.'),
        isTrue);

    var last = clean[(clean.length - 2)];
    expect(last.startsWith('ONEPUB_SECRET='), isTrue);

    // check the secret has a guid
    var parts = last.split('=');
    expect(parts.length, equals(2));
    expect(parts[1].length, equals(36));
  });
}
