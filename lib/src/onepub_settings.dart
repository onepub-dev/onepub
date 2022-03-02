import 'dart:io';
import 'dart:math';

import 'package:dcli/dcli.dart';
import 'package:meta/meta.dart';
import 'package:settings_yaml/settings_yaml.dart';
import 'package:yaml/yaml.dart';

import 'onepub_paths.dart';
import 'util/log.dart';

void loadSettings() {
  if (!exists(OnePubSettings.pathToSettings)) {
    logerr(red('''You must run 'onepub install' first.'''));
    exit(1);
  }
  OnePubSettings.load();
}

class OnePubSettings {
  factory OnePubSettings() => _self!;

  ///
  factory OnePubSettings.load({bool showWarnings = false}) {
    if (_self != null) {
      return _self!;
    }

    try {
      final settings = SettingsYaml.load(pathToSettings: pathToSettings);
      _self =
          OnePubSettings.loadFromSettings(settings, showWarnings: showWarnings);
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
  OnePubSettings.loadFromSettings(this.settings, {required this.showWarnings});

  static const pubHostedUrlKey = 'PUB_HOSTED_URL';

  static OnePubSettings? _self;

  bool showWarnings;

  late final SettingsYaml settings;

  /// Path to the onepub onepub.yaml file.
  static late final String pathToSettings =
      join(OnePubPaths().pathToSettingsDir, 'onepub.yaml');

  static const String defaultOnePubWebUrl = 'https://onepub.dev';
  static const String defaultOnePubApiUrl = 'https://onepub.dev';

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
      settings.asString('apiUrl', defaultValue: defaultOnePubApiUrl),
      defaultApiBasePath);

  set onepubApiUrl(String url) => settings['apiUrl'] = url;

  set obfuscatedPublisherId(String obfuscatedPublisherId) =>
      settings['publisherId'] = obfuscatedPublisherId;

  String get obfuscatedPublisherId => join(
        settings.asString('publisherId', defaultValue: defaultOnePubApiUrl),
      );

  set publisherName(String publisherName) =>
      settings['publisherName'] = publisherName;

  String get publisherName => join(
        settings.asString('publisherName'),
      );

  ///
  String get onepubWebUrl => join(
      settings.asString('webUrl', defaultValue: defaultOnePubWebUrl),
      defaultWebBasePath);

  static String onepubTokenKey = 'onepubToken';

  void save() => settings.save();

  String resolveApiEndPoint(String command, {String? queryParams}) {
    if (command.startsWith('/')) {
      // ignore: parameter_assignments
      command = command.substring(1);
    }
    var endpoint = join(OnePubSettings().onepubApiUrl, command);

    if (queryParams != null) {
      endpoint += '?$queryParams';
    }
    return endpoint;
  }

  String resolveWebEndPoint(String command, {String? queryParams}) {
    var endpoint = join(OnePubSettings().onepubWebUrl, command);

    if (queryParams != null) {
      endpoint += '?$queryParams';
    }
    return endpoint;
  }
}

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
