/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'package:dcli/dcli.dart';
import 'package:onepub/src/entry_point.dart';
import 'package:onepub/src/global_args.dart';
import 'package:test/test.dart';

void main() {
  test('add_dependency ...', () async {
    Settings().setVerbose(enabled: true);
    entrypoint(['add', 'node_mgmt_lib', '^0.3.3'], CommandSet.ONEPUB, 'onepub');
  });
}
