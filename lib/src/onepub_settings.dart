import 'dart:io';
import 'dart:math';

import 'package:dcli/dcli.dart';
import 'package:meta/meta.dart';
import 'package:settings_yaml/settings_yaml.dart';
import 'package:yaml/yaml.dart';

import 'onepub_paths.dart';
import 'util/log.dart';

void loadSettings() {
  if (!exists(OnepubSettings.pathToSettings)) {
    logerr(red('''You must run 'onepub install' first.'''));
    exit(1);
  }
  OnepubSettings.load();
}

class OnepubSettings {
  factory OnepubSettings() => _self!;

  ///
  factory OnepubSettings.load({bool showWarnings = false}) {
    if (_self != null) {
      return _self!;
    }

    try {
      final settings = SettingsYaml.load(pathToSettings: pathToSettings);
      _self =
          OnepubSettings.loadFromSettings(settings, showWarnings: showWarnings);
      return _self!;
    } on YamlException catch (e) {
      logerr(red('Failed to load rules from $pathToSettings'));
      logerr(red(e.toString()));
      rethrow;
    } on RulesException catch (e) {
      logerr(red('Failed to load rules from $pathToSettings'));
      logerr(red(e.message));
      rethrow;
    }
  }

  @visibleForTesting
  OnepubSettings.loadFromSettings(this.settings, {required this.showWarnings});

  static const pubHostedUrlKey = 'PUB_HOSTED_URL';

  static OnepubSettings? _self;

  bool showWarnings;

  late final SettingsYaml settings;

  /// Path to the onepub onepub.yaml file.
  static late final String pathToSettings =
      join(OnepubPaths().pathToSettingsDir, 'onepub.yaml');

  String get onepubApiUrl => 'http://$host:$port';

  static const String onepubWebUrl = 'https://onepub.dev';

  ///
  String get host => settings.asString('host', defaultValue: 'onepub.dev');
  set host(String host) => settings['host'] = host;

  ///
  String get port => settings.asString('port', defaultValue: '443');
  set port(String port) => settings['port'] = port;

  static String onepubTokenKey = 'onepubToken';

  /// oauth2
  bool get hasToken => settings.validString(onepubTokenKey);
  String get onepubToken => settings.asString(onepubTokenKey);
  set onepubToken(String token) => settings[onepubTokenKey] = token;


  bool get isLoggedIn => hasToken;

  void save() => settings.save();
}

bool get isLoggedIn => OnepubSettings().isLoggedIn;

///
class RulesException implements Exception {
  ///
  RulesException(this.message);
  String message;

  @override
  String toString() => message;
}

String generateRandomString(int len) {
  final r = Random();
  const _chars =
      'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz1234567890';
  return List.generate(len, (index) => _chars[r.nextInt(_chars.length)]).join();
}
