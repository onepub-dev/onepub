import 'package:dcli/dcli.dart';

class OnepubPaths {
  factory OnepubPaths() => _self;

  factory OnepubPaths.forTest(String settingsRoot) =>
      _self = OnepubPaths._internal(settingsRoot);

  OnepubPaths._internal(this._settingsRoot);

  static OnepubPaths _self = OnepubPaths._internal(HOME);

  /// Path to the .batman settings directory
  late final String pathToSettingsDir =
      env['ONEPUB_PATH'] ?? join(_settingsRoot, '.onepub');

  late final String pathToDotEnv = join(pathToSettingsDir, '.env');

  final String _settingsRoot;
}
