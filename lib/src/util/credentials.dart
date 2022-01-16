import 'package:dcli/dcli.dart';
import 'package:meta/meta.dart';
import 'package:settings_yaml/settings_yaml.dart';
import 'package:yaml/yaml.dart';

import '../exceptions.dart';
import '../onepub_paths.dart';
import 'log.dart';

/// Used to export the onepub credentials as a yaml file.
class Credentials {
  factory Credentials() => _self!;

  ///
  factory Credentials.load(String pathToCredentials) {
    if (_self != null) {
      return _self!;
    }

    final file = join(pathToCredentials, credentialsFileName);
    try {
      final settings = SettingsYaml.load(pathToSettings: file);
      _self = Credentials.loadFromSettings(settings);
      return _self!;
    } on YamlException catch (e) {
      logerr(red('Failed to load credentials from $file'));
      logerr(red(e.toString()));
      throw CredentialsException(message: e.toString());
    }
  }

  @visibleForTesting
  Credentials.loadFromSettings(this.settings);

  static const credentialsFileName = 'onepub.credentials.json';

  static late final String pathToCredentials =
      join(OnepubPaths().pathToSettingsDir, credentialsFileName);

  static const onepubSecretEnvKey = 'ONEPUB_SECRET';

  /// oauth2
  static String oauth2TokenKey = 'oauth2Token';
  bool get hasToken => settings.validString(oauth2TokenKey);
  String get oauth2Token => settings.asString(oauth2TokenKey);
  set oauth2Token(String token) => settings[oauth2Token] = token;

  static Credentials? _self;

  late final SettingsYaml settings;

  void save() => settings.save();
}
