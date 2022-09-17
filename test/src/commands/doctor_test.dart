/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'package:dcli/dcli.dart';
import 'package:onepub/src/version/version.g.dart';
import 'package:test/test.dart';

import '../test_settings.dart';
import 'test_utils.dart';

void main() {
  test('onepub doctor ...', () async {
    await withTestSettings((testSettings) async {
      final clean = runCmd('doctor');

      final first = clean.first;
      expect(first, 'OnePub version: $packageVersion ');

      final status = clean[(clean.length - 4)];
      expect(status, 'OnePub: status healthy.');

      final version = clean[(clean.length - 2)];
      expect(version.startsWith('Server Version'), isTrue);

      // check that we have each of the major headings
      expect(clean.contains('Platform'), isTrue);
      expect(
          clean.any((element) =>
              element.contains('Dart version:') &&
              element.contains(DartSdk().version)),
          isTrue);
      expect(clean.contains('URLs'), isTrue);
      expect(clean.contains('Environment'), isTrue);
      expect(clean.contains('Repository tokens'), isTrue);
      expect(clean.contains('Status'), isTrue);
    });
  });
}
