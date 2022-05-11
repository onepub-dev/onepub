/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'package:onepub/src/entry_point.dart';
import 'package:onepub/src/global_args.dart';
import 'package:test/test.dart';

void main() {
  test('login ...', () async {
    entrypoint(['login'], CommandSet.ONEPUB, 'onepub');
  });
}
