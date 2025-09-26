/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */
import 'dart:io';

import 'package:dcli_core/dcli_core.dart';
import 'package:dcli_input/dcli_input.dart';
import 'package:dcli_terminal/dcli_terminal.dart';
import 'package:path/path.dart';
import 'package:scope/scope.dart';
import 'package:settings_yaml/settings_yaml.dart';
import 'package:url_builder/url_builder.dart';
import 'package:yaml/yaml.dart';

import 'exceptions.dart';
import 'util/hosted.dart';
import 'util/log.dart';
import 'util/string_extension.dart';
import 'util/url_validator.dart';
import 'version/version.g.dart';

/// The ~/onepub/onepub.yaml
class OnePubSettings {
  ///////////////
  ///
  ///Fields
  ///
  /////////////////////

  /// Path to the onepub settings file
  late final String pathToSettings;

  late final SettingsYaml _settings;

  static const scopeKey = ScopeKey<OnePubSettings>('OnePubSettings');

  static const onepubServerUrlKey = 'onepubUrl';

  static const defaultOnePubUrl = 'https://onepub.dev';

  static const _defaultApiBasePath = 'api';

  ///static const String defaultWebBasePath = 'ui';
  static const _defaultWebBasePath = '';

  // Key of environment var used to alter the
  // path to looking for the settings.
  static const onepubPathEnvKey = 'ONEPUB_PATH';

  /// allowBadCertificates
  /// During dev if we are using self signed cert we need to set this
  static const allowBadCertificatesKey = 'allowBadCertificates';

  /// The url to the currently logged in organisation
  static var reportedNonStandard = false;

  final testingFlagPath = join(HOME, '.onepubtesting');

  OnePubSettings({String? pathToSettings}) {
    this.pathToSettings = pathToSettings ?? defaultPathToSettings;

    if (!exists(dirname(this.pathToSettings))) {
      createDir(dirname(this.pathToSettings), recursive: true);
    }

    _settings = SettingsYaml.load(pathToSettings: this.pathToSettings);
  }

  ///
  /// Loads the [OnePubSettings] from the default location
  /// unless the ONEPUB_PATH env var exists and then we
  /// load from that path.
  OnePubSettings._load({required bool create}) {
    if (create) {
      if (!exists(defaultPathToSettings)) {
        _create(pathToDir: defaultPathToSettings);
      }
    }
    _settings = _loadYaml(pathToDir: defaultPathToSettingsDir);
  }

  /// [pathToDir] the directory to load the settings file from.
  /// If [create] is true then the settings file and directory will be
  /// created.
  /// if [create] is true and the settings file already exists then
  /// a [ExitException] will be thrown.
  OnePubSettings._loadFromPath(
      {required String pathToDir, required bool create}) {
    if (create) {
      if (!exists(pathToDir)) {
        _create(pathToDir: pathToDir);
      }
    }
    _settings = _loadYaml(pathToDir: pathToDir);
  }

  /// Call [use] to obtain the current OnePubSettings file.
  /// If no scope exists we return the settings file stored
  /// at the default location ~/onepub/onepub.yaml
  factory OnePubSettings.use() => Scope.use(scopeKey,
      withDefault: () => OnePubSettings._load(create: false));

  /// Creates the onepub.yaml file at [defaultPathToSettingsDir] but does not
  /// initialise nor load it.
  static void _create({required String pathToDir}) {
    final pathToSettingsFile =
        join(defaultPathToSettingsDir, defaultSettingsFilename);
    if (exists(pathToSettingsFile)) {
      final message =
          'The OnePubSettings file at $pathToSettingsFile alread exists.';
      logerr(red(message));
      throw ExitException(exitCode: 1, message: message);
    }
    if (!exists(defaultPathToSettingsDir)) {
      createDir(defaultPathToSettingsDir, recursive: true);
    }
    touch(pathToSettingsFile, create: true);
  }

  static SettingsYaml _loadYaml({required String pathToDir}) {
    final pathToFile = join(pathToDir, defaultSettingsFilename);
    try {
      return SettingsYaml.load(pathToSettings: pathToFile);
    } on YamlException catch (e) {
      logerr(red('Failed to load rules from $pathToFile'));
      logerr(red(e.toString()));
      rethrow;
    } on RulesException catch (e) {
      logerr(red('Failed to load rules from $pathToFile'));
      logerr(red(e.message));
      rethrow;
    }
  }

  /// Loads a [OnePubSettings] file located
  /// in the directory [pathToSettingsDir]
  /// into a new scope.
  static Future<T> withPathTo<T>(
      String pathToSettingsDir, Future<T> Function() action) {
    final innerSettings = OnePubSettings._loadFromPath(
        pathToDir: pathToSettingsDir, create: true);

    final scope = Scope()..value(scopeKey, innerSettings);

    return scope.run<T>(() => action());
  }

  /// Path to the .onepub settings directory
  static String get defaultPathToSettingsDir {
    final pathToSettings = env[onepubPathEnvKey] ?? join(HOME, '.onepub');

    return pathToSettings;
  }

  static String get defaultSettingsFilename => 'onepub.yaml';

  /// Path to the onepub onepub.yaml file.
  static String get defaultPathToSettings =>
      join(defaultPathToSettingsDir, defaultSettingsFilename);

  bool get allowBadCertificates =>
      _settings.asBool(allowBadCertificatesKey, defaultValue: false);

  /// The pub token command strips the port if its 443 so we must as well.
  /// The result is of the form: http://onepub.dev/api
  /// However the current settings path may have a different fqdn.
  String get _buildBaseApiUrl => urlJoin(
      _settings.asString(onepubServerUrlKey, defaultValue: defaultOnePubUrl),
      _defaultApiBasePath);

  /// Return the onepub url to the api endpoint
  Uri get onepubApiUrl => validateAndNormalizeHostedUrl(onepubApiUrlAsString);

  /// Return the onepub url to the api endpoint
  String get onepubApiUrlAsString {
    final baseApiUrl = _buildBaseApiUrl;

    final url = '$baseApiUrl/$obfuscatedOrganisationId/';
    return url;
  }

  // onepubWebUrl
  String get onepubWebUrl => urlJoin(
      _settings.asString(onepubServerUrlKey, defaultValue: defaultOnePubUrl),
      _defaultWebBasePath);

  String get docsOnePubUrl =>
      'https://docs.onepub.dev';


String get guidePublishOnePubUrl =>
      urlJoin(OnePubSettings.use().docsOnePubUrl, '/guides/publishing-packages');

  // onepub url
  set onepubUrl(String? url) => _settings[onepubServerUrlKey] = url;

  String? get onepubUrl => _settings[onepubServerUrlKey] as String?;

  // obfuscated id
  set obfuscatedOrganisationId(String obfuscatedOrganisationId) =>
      _settings['organisationId'] = obfuscatedOrganisationId;

  String get obfuscatedOrganisationId => _settings.asString('organisationId',
      defaultValue: 'OrganisationId_not_set');

  // organisationName
  String get organisationName => _settings.asString('organisationName');

  set organisationName(String organisationName) {
    _settings['organisationName'] = organisationName;
  }

  // operatorEmail
  set operatorEmail(String operatorEmail) =>
      _settings['operatorEmail'] = operatorEmail;

  String get operatorEmail => _settings.asString('operatorEmail');

  Future<void> save() => _settings.save();

  Future<void> saveTo(String tempSettingsDir) async {
    _settings.filePath = join(tempSettingsDir, defaultSettingsFilename);
    await _settings.save();
  }

  String resolveApiEndPoint(String command, {String? queryParams}) {
    var endpoint = urlJoin(_buildBaseApiUrl, command);

    if (queryParams != null) {
      endpoint += '?$queryParams';
    }
    return endpoint;
  }

  String resolveWebEndPoint(String command, {String? queryParams}) {
    var endpoint = urlJoin(onepubWebUrl, command);

    if (queryParams != null) {
      endpoint += '?$queryParams';
    }
    return endpoint;
  }

  static Future<void> install({required bool dev}) async {
    final create = !exists(defaultPathToSettings);
    final settings = OnePubSettings._load(create: create);

    if (create) {
      // creaet default settings file.
      defaultPathToSettings.write('version: 1');
    }

    if (settings.onepubUrl == null || settings.onepubUrl!.isEmpty || dev) {
      await settings.config(dev: dev);

      print(orange('Installed OnePub version: $packageVersion.'));
    }

    if (exists(settings.testingFlagPath)) {
      if (settings.onepubUrl == OnePubSettings.defaultOnePubUrl) {
        print('This system is configured for testing, but is also configured'
            ' with the production URL. If you need to change this, then delete '
            '${settings.testingFlagPath} or use the --dev option to '
            'change the URL');
        exit(1);
      }
    }
  }

  ///
  Future<void> config({required bool dev}) async {
    print('Configure OnePub');

    await promptForConfig(dev: dev);
  }

  Future<void> promptForConfig({required bool dev}) async {
    var url = OnePubSettings.defaultOnePubUrl;
    if (dev) {
      print('Configure OnePub');
      url = await ask('OnePub URL:',
          validator: UrlValidator(), defaultValue: url);
      testingFlagPath.write('onepubtesting');
    }

    final settings = OnePubSettings.use()..onepubUrl = url;
    await settings.save();
  }

  /// If the settings are using a non-standard url (e.g. not https;//onepub.dev)
  /// print a warning.
  void nonStandardUrlWarning() {
    if (_buildBaseApiUrl != '${OnePubSettings.defaultOnePubUrl}/api') {
      print(red('Using non-standard OnePub API url $_buildBaseApiUrl'));
      print('');
    }
  }
}

// void a() {
//   One
// }
