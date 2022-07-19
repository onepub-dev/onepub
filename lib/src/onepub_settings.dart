/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */
import 'dart:math';

import 'package:dcli/dcli.dart';
import 'package:scope/scope.dart';
import 'package:settings_yaml/settings_yaml.dart';
import 'package:url_builder/url_builder.dart';
import 'package:yaml/yaml.dart';

import 'exceptions.dart';
import 'onepub_paths.dart';
import 'pub/source/hosted.dart';
import 'util/log.dart';

class OnePubSettings {
  ///
  OnePubSettings._internal({required bool create}) {
    if (!exists(pathToSettings)) {
      if (create) {
        if (!exists(pathToSettingsDir)) {
          createDir(pathToSettingsDir, recursive: true);
        }
        touch(pathToSettings, create: true);
      } else {
        logerr(red('''Something went wrong, could not find settings file.'''));
        throw ExitException(
            exitCode: 1,
            message: 'Something went wrong, could not find settings file.');
      }
    }

    try {
      _settings = SettingsYaml.load(pathToSettings: pathToSettings);
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

  static final scopeKey = ScopeKey<OnePubSettings>('OnePubSettings');
  static OnePubSettings get use => Scope.use(scopeKey);

  static const pubHostedUrlKey = 'onepubUrl';
  late final SettingsYaml _settings;

  static const String defaultOnePubUrl = 'https://onepub.dev';

  static const String _defaultApiBasePath = 'api';

  ///static const String defaultWebBasePath = 'ui';
  static const String _defaultWebBasePath = '';

  // Key of environement var used to alter the
  // path to looking for the settings.
  static const onepubPathEnvKey = 'ONEPUB_PATH';

  /// Path to the .onepub settings directory
  String get pathToSettingsDir {
    final pathToSettings = env[onepubPathEnvKey] ?? join(HOME, '.onepub');

    return pathToSettings;
  }

  /// Path to the onepub onepub.yaml file.
  String get pathToSettings => join(pathToSettingsDir, 'onepub.yaml');

  /// allowBadCertificates
  /// During dev if we are using self signed cert we need to set this
  static const String allowBadCertificatesKey = 'allowBadCertificates';
  bool get allowBadCertificates =>
      _settings.asBool(allowBadCertificatesKey, defaultValue: false);

  /// pub token add strips the port if its 443 so we must as well
  /// so our process of checking that the url has been added to the
  /// token list works.
  String get onepubApiUrl => urlJoin(
      _settings.asString(pubHostedUrlKey, defaultValue: defaultOnePubUrl),
      _defaultApiBasePath);

  /// The url to the currently logged in organisation
  bool reportedNonStandard = false;
  Uri onepubHostedUrl([String? obfuscatedOrganisationId]) {
    final settings = OnePubSettings.use;
    obfuscatedOrganisationId ??= settings.obfuscatedOrganisationId;
    final apiUrl = settings.onepubApiUrl;
    if (!reportedNonStandard &&
        apiUrl != '${OnePubSettings.defaultOnePubUrl}/api') {
      print(red('Using non-standard OnePub API url $apiUrl'));
      print('');
      reportedNonStandard = true;
    }
    final url = '$apiUrl/$obfuscatedOrganisationId/';
    return validateAndNormalizeHostedUrl(url);
  }

  String get onepubWebUrl => urlJoin(
      _settings.asString(pubHostedUrlKey, defaultValue: defaultOnePubUrl),
      _defaultWebBasePath);

  set onepubUrl(String? url) => _settings[pubHostedUrlKey] = url;

  String? get onepubUrl => _settings[pubHostedUrlKey] as String?;

  set obfuscatedOrganisationId(String obfuscatedOrganisationId) =>
      _settings['organisationId'] = obfuscatedOrganisationId;
  String get obfuscatedOrganisationId => _settings.asString('organisationId',
      defaultValue: 'OrganisationId_not_set');

  String get organisationName => _settings.asString('organisationName');

  set organisationName(String organisationName) {
    _settings['organisationName'] = organisationName;
  }

  set operatorEmail(String operatorEmail) =>
      _settings['operatorEmail'] = operatorEmail;
  String get operatorEmail => _settings.asString('operatorEmail');

  void save() => waitForEx(_settings.save());

  String resolveApiEndPoint(String command, {String? queryParams}) {
    var endpoint = urlJoin(OnePubSettings.use.onepubApiUrl, command);

    if (queryParams != null) {
      endpoint += '?$queryParams';
    }
    return endpoint;
  }

  String resolveWebEndPoint(String command, {String? queryParams}) {
    var endpoint = urlJoin(OnePubSettings.use.onepubWebUrl, command);

    if (queryParams != null) {
      endpoint += '?$queryParams';
    }
    return endpoint;
  }
}

void withSettings(void Function() action, {bool create = false}) {
  withPaths(() => Scope()
    ..value<OnePubSettings>(
        OnePubSettings.scopeKey, OnePubSettings._internal(create: create))
    ..run(() {
      action();
    }));
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
