/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'package:onepub/src/version/version.g.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  test('onepub doctor ...', () async {
    var clean = runCmd('doctor');

    var first = clean.first;
    expect(first, 'OnePub version: $packageVersion ');

    var last = clean[(clean.length - 2)];
    expect(last, 'OnePub: status healthy.');

    // check that we have each of the major headings
    expect(clean.contains('Dart'), isTrue);
    expect(clean.contains('URLs'), isTrue);
    expect(clean.contains('Environment'), isTrue);
    expect(clean.contains('Repository tokens'), isTrue);
    expect(clean.contains('Status'), isTrue);
  });
}
