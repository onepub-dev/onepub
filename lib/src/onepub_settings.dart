/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */
import 'dart:io';
import 'dart:math';

import 'package:dcli/dcli.dart';
import 'package:meta/meta.dart';
import 'package:onepub/src/pub/source/hosted.dart';
import 'package:settings_yaml/settings_yaml.dart';
import 'package:yaml/yaml.dart';
import 'package:url_builder/url_builder.dart';

import 'onepub_paths.dart';
import 'util/log.dart';

void loadSettings() {
  if (!exists(OnePubSettings.pathToSettings)) {
    logerr(red('''Something went wrong, could not find settings file.'''));
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

  static const pubHostedUrlKey = 'onepubUrl';

  static OnePubSettings? _self;

  bool showWarnings;

  late final SettingsYaml settings;

  /// Path to the onepub onepub.yaml file.
  static late final String pathToSettings =
      join(OnePubPaths().pathToSettingsDir, 'onepub.yaml');

  static const String defaultOnePubUrl = 'https://onepub.dev';

  static const String _defaultApiBasePath = 'api';

  ///static const String defaultWebBasePath = 'ui';
  static const String _defaultWebBasePath = '';

  /// allowBadCertificates
  /// During dev if we are using self signed cert we need to set this
  static String allowBadCertificatesKey = 'allowBadCertificates';
  bool get allowBadCertificates =>
      settings.asBool(allowBadCertificatesKey, defaultValue: false);

  /// pub token add strips the port if its 443 so we must as well
  /// so our process of checking that the url has been added to the
  /// token list works.
  String get onepubApiUrl => urlJoin(
      settings.asString(pubHostedUrlKey, defaultValue: defaultOnePubUrl),
      _defaultApiBasePath);

  /// The url to the currently logged in organisation
  static bool reportedNonStandard = false;
  Uri onepubHostedUrl([String? obfuscatedOrganisationId]) {
    obfuscatedOrganisationId ??= OnePubSettings().obfuscatedOrganisationId;
    final apiUrl = OnePubSettings().onepubApiUrl;
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
      settings.asString(pubHostedUrlKey, defaultValue: defaultOnePubUrl),
      _defaultWebBasePath);

  set onepubUrl(String? url) => settings[pubHostedUrlKey] = url;

  String? get onepubUrl => settings[pubHostedUrlKey] as String?;

  set obfuscatedOrganisationId(String obfuscatedOrganisationId) =>
      settings['organisationId'] = obfuscatedOrganisationId;

  String get obfuscatedOrganisationId => settings.asString('organisationId',
      defaultValue: 'OrganisationId_not_set');

  set organisationName(String organisationName) =>
      settings['organisationName'] = organisationName;

  set operatorEmail(String operatorEmail) =>
      settings['operatorEmail'] = operatorEmail;

  String get organisationName => settings.asString('organisationName');
  String get operatorEmail => settings.asString('operatorEmail');

  void save() => settings.save();

  String resolveApiEndPoint(String command, {String? queryParams}) {
    var endpoint = urlJoin(OnePubSettings().onepubApiUrl, command);

    if (queryParams != null) {
      endpoint += '?$queryParams';
    }
    return endpoint;
  }

  String resolveWebEndPoint(String command, {String? queryParams}) {
    var endpoint = urlJoin(OnePubSettings().onepubWebUrl, command);

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
