/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'package:dcli_core/dcli_core.dart';
import 'package:onepub/src/entry_point.dart';
import 'package:onepub/src/my_runner.dart';
import 'package:onepub/src/onepub_settings.dart';
import 'package:test/test.dart';

void main() {
  test('login clean', () async {
    await withTempDir((tempDir) async {
      await withEnvironment(() async {
        await entrypoint(['login'], CommandSet.onepub, 'onepub');
      }, environment: {OnePubSettings.onepubPathEnvKey: tempDir});
    });
  }
      // , tags: ['manual']
      );
}
