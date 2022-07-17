/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */
import 'package:dcli/dcli.dart';
import 'package:scope/scope.dart';

final scopeKeyPathToSettings = ScopeKey<String>('pathToSettings');

class OnePubPaths {
  factory OnePubPaths() => _self;

  OnePubPaths._internal(this._settingsRoot);

  static final OnePubPaths _self = OnePubPaths._internal(HOME);

  /// Path to the .batman settings directory
  String get pathToSettingsDir {
    var pathToSettings = env['ONEPUB_PATH'] ?? join(_settingsRoot, '.onepub');

    // used by unit tests
    if (Scope.hasScopeKey(scopeKeyPathToSettings)) {
      pathToSettings = Scope.use(scopeKeyPathToSettings);
    }
    return pathToSettings;
  }

  String get pathToTestSettings {
    final pathToTest = DartProject.self.pathToTestDir;

    return join(pathToTest, 'test_settings.yaml');
  }

  final String _settingsRoot;
}
