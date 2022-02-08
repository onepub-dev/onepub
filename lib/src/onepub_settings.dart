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

  static const String defaultOnepubWebUrl = 'https://onepub.dev';
  static const String defaultOnepubApiUrl = 'https://onepub.dev';

  static const String defaultApiBasePath = 'api';

  ///static const String defaultWebBasePath = 'ui';
  static const String defaultWebBasePath = '';

  /// allowBadCertificates
  /// During dev if we are using self signed cert we need to set this
  static String allowBadCertificatesKey = 'allowBadCertificates';
  bool get allowBadCertificates =>
      settings.asBool(allowBadCertificatesKey, defaultValue: false);

  /// pub token add strips the port if its 443 so we must as well
  /// so our process of checking that the url has been added to the
  /// token list works.
  String get onepubApiUrl => join(
      settings.asString('apiUrl', defaultValue: defaultOnepubApiUrl),
      defaultApiBasePath);

  set onepubApiUrl(String url) => settings['apiUrl'] = url;

  ///
  String get onepubWebUrl => join(
      settings.asString('webUrl', defaultValue: defaultOnepubWebUrl),
      defaultWebBasePath);

  static String onepubTokenKey = 'onepubToken';

  /// oauth2
  bool get hasToken => settings.validString(onepubTokenKey);
  String get onepubToken => settings.asString(onepubTokenKey);
  set onepubToken(String token) => settings[onepubTokenKey] = token;

  bool get isLoggedIn => hasToken;

  void save() => settings.save();

  String resolveApiEndPoint(String command, {String? queryParams}) {
    if (command.startsWith('/')) {
      // ignore: parameter_assignments
      command = command.substring(1);
    }
    var endpoint = join(OnepubSettings().onepubApiUrl, command);

    if (queryParams != null) {
      endpoint += '?$queryParams';
    }
    return endpoint;
  }

  String resolveWebEndPoint(String command, {String? queryParams}) {
    var endpoint = join(OnepubSettings().onepubWebUrl, command);

    if (queryParams != null) {
      endpoint += '?$queryParams';
    }
    return endpoint;
  }
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
