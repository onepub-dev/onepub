/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'package:dcli/dcli.dart' hide equals;
import 'package:test/test.dart';

void main() {
  test('add_dependency ...', () async {
    Settings().setVerbose(enabled: false);
    // entrypoint(['add', 'node_mgmt_lib', '^0.3.3'], CommandSet.ONEPUB, 'onepub');
    // entrypoint(['add', 'node_mgmt_lib'], CommandSet.ONEPUB, 'onepub');

    var pathToRoot = DartProject.self.pathToProjectRoot;
    var pathToOnePub = join(pathToRoot, 'bin', 'onepub.dart');
    withTempDir((workingDir) {
      copyTree(
          join(pathToRoot, 'test', 'fixtures', 'test_packag_1'), workingDir);

      var pathToPubSpec = join(workingDir, 'pubspec.yaml');
      var pubSpec = PubSpec.fromFile(pathToPubSpec);
      expect(pubSpec.dependencies.containsKey('node_mgmt_lib'), isFalse);

      // run add dep
      var progress = 'dart $pathToOnePub add node_mgmt_lib'
          .start(workingDirectory: workingDir);
      expect(progress.exitCode, equals(0));

      pubSpec = PubSpec.fromFile(pathToPubSpec);
      expect(pubSpec.dependencies.containsKey('node_mgmt_lib'), isTrue);
    });
  });
}
