/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'package:onepub/src/entry_point.dart';
import 'package:test/test.dart';

void main() {
  test('logout ...', () async {
    await entrypoint(['logout'], 'onepub');
    // });
  }, tags: ['manual']);
}
