import 'package:dcli/dcli.dart';
import 'package:onepub/src/onepub_paths.dart';
import 'package:onepub/src/onepub_settings.dart';
import 'package:settings_yaml/settings_yaml.dart';

class TestSettings {
  TestSettings() {
    _settings =
        SettingsYaml.load(pathToSettings: OnePubPaths.use.pathToTestSettings);
  }

  late final SettingsYaml _settings;

  String get member => _settings.asString('member');
  String get cicdMember => _settings.asString('cicd_member');

  String get onepubToken => _settings.asString('onepub_token');
  set onepubToken(String token) => _settings['onepub_token'] = token;

  String get onepubUrl => _settings.asString('onepubUrl');
  set onepubUrl(String url) => _settings['onepubUrl'] = url;

  String get organisationName => _settings.asString('organisationName');

  set organisationName(String name) => _settings['organisationName'] = name;

  String get organisationId => _settings.asString('organisationId');
  set organisationId(String obsfucatedId) =>
      _settings['organisationId'] = obsfucatedId;

  void save() => waitForEx(_settings.save());
}

void withTestSettings(void Function(TestSettings testSettings) action,
    {bool forAuthentication = false}) {
  withTempDir((tempSettingsDir) {
    withEnvironment(() {
      withPaths(() {
        withSettings(() {
          final settings = OnePubSettings.use;
          final testSettings = TestSettings();

          if (!forAuthentication) {
            settings
              ..organisationName = testSettings.organisationName
              ..obfuscatedOrganisationId = testSettings.organisationId;
          }
          settings
            ..onepubUrl = testSettings.onepubUrl
            ..save();

          action(testSettings);
        }, create: true);
      });
    }, environment: {OnePubSettings.onepubPathEnvKey: tempSettingsDir});
  });
}
