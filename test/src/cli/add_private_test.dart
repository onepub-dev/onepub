/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'package:dcli/dcli.dart' hide equals;
import 'package:test/test.dart';

void main() {
  test('add_dependency ...', () async {
    Settings().setVerbose(enabled: false);

    var pathToRoot = DartProject.self.pathToProjectRoot;
    var pathToOnePub = join(pathToRoot, 'bin', 'onepub.dart');
    withTempDir((workingDir) {
      copyTree(
          join(pathToRoot, 'test', 'fixtures', 'test_packag_1'), workingDir);

      var pathToPubSpec = join(workingDir, 'pubspec.yaml');
      var pubSpec = PubSpec.fromFile(pathToPubSpec);
      expect(pubSpec.dependencies.containsKey('node_mgmt_lib'), isFalse);

      // run onepub add <dep>
      var progress = 'dart $pathToOnePub add node_mgmt_lib'
          .start(workingDirectory: workingDir);
      expect(progress.exitCode, equals(0));

      pubSpec = PubSpec.fromFile(pathToPubSpec);
      expect(pubSpec.dependencies.containsKey('node_mgmt_lib'), isTrue);
    });
  });
}
