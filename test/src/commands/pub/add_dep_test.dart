/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'package:dcli/dcli.dart' hide equals;
import 'package:onepub/src/entry_point.dart';
import 'package:onepub/src/my_runner.dart';
import 'package:scope/scope.dart';
import 'package:test/test.dart';

import '../test_utils.dart';

void main() {
  test('add_dependency ...', () async {
    Settings().setVerbose(enabled: false);

    withTempProject('test_packag_1', (dartProject) {
      var pubSpec = dartProject.pubSpec;
      expect(pubSpec.dependencies.containsKey('node_mgmt_lib'), isFalse);

      // run onepub add <dep>
      final progress = 'dart $pathToOnePubScript pub add node_mgmt_lib'
          .start(workingDirectory: dartProject.pathToProjectRoot);
      expect(progress.exitCode, equals(0));

      // load the updated pubspec
      pubSpec = PubSpec.fromFile(dartProject.pathToPubSpec);
      expect(pubSpec.dependencies.containsKey('node_mgmt_lib'), isTrue);
    });
  });

  test('cli: entrypoint ...', () async {
    const packageName = 'test_packag_1';
    withTempProject(packageName, (dartProject) {
      final size = stat(dartProject.pathToPubSpec).size;
      Scope()
        ..value(unitTestWorkingDirectoryKey, dartProject.pathToProjectRoot)
        ..run(() {
          waitForEx(entrypoint(
              ['pub', 'add', 'node_mgmt_lib'], CommandSet.onepub, 'onepub'));
        });
      expect(stat(dartProject.pathToPubSpec).size, greaterThan(size));
    });
  }, skip: true);
}
