/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */
import 'package:dcli/dcli.dart';
import 'package:scope/scope.dart';

class OnePubPaths {
  OnePubPaths._internal(); // this._settingsRoot);

  static OnePubPaths get use => Scope.use(scopeKey);

  static final scopeKey = ScopeKey<OnePubPaths>('OnePubPaths');

  String get pathToTestSettings {
    final pathToTest = DartProject.self.pathToTestDir;

    return join(pathToTest, 'test_settings.yaml');
  }

  // final String _settingsRoot;
}

void withPaths(void Function() action) {
  Scope()
    ..value(OnePubPaths.scopeKey, OnePubPaths._internal())
    ..run(() {
      action();
    });
}
