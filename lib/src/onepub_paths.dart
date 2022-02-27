import 'package:dcli/dcli.dart';

class OnePubPaths {
  factory OnePubPaths() => _self;

  factory OnePubPaths.forTest(String settingsRoot) =>
      _self = OnePubPaths._internal(settingsRoot);

  OnePubPaths._internal(this._settingsRoot);

  static OnePubPaths _self = OnePubPaths._internal(HOME);

  /// Path to the .batman settings directory
  late final String pathToSettingsDir =
      env['ONEPUB_PATH'] ?? join(_settingsRoot, '.onepub');

  late final String pathToDotEnv = join(pathToSettingsDir, '.env');

  final String _settingsRoot;
}
