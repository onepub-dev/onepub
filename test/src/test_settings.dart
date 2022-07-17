import 'package:onepub/src/onepub_paths.dart';
import 'package:settings_yaml/settings_yaml.dart';

class TestSettings {
  TestSettings() {
    _settings =
        SettingsYaml.load(pathToSettings: OnePubPaths().pathToTestSettings);
  }

  late final SettingsYaml _settings;

  String get member => _settings.asString('member');
  String get cicd_member => _settings.asString('cicd_member');

  String get onepubToken => _settings.asString('onepub_token');
}
