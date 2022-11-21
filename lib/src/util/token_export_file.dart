/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */
import 'package:dcli/dcli.dart';
import 'package:settings_yaml/settings_yaml.dart';
import 'package:yaml/yaml.dart';

import '../exceptions.dart';
import 'log.dart';

/// Used to export the onepub credentials as a yaml file.
class TokenExportFile {
  TokenExportFile(this.pathToExportFile) {
    settings = SettingsYaml.load(pathToSettings: pathToExportFile);
  }

  ///
  TokenExportFile.load(this.pathToExportFile) {
    try {
      settings = SettingsYaml.load(pathToSettings: pathToExportFile);
    } on YamlException catch (e) {
      logerr(red('Failed to load credentials from $pathToExportFile'));
      logerr(red(e.toString()));
      throw CredentialsException(e.toString());
    }
  }

  static String onepubTokenKey = 'onepubToken';
  static const exportFilename = 'onepub.token.yaml';

  late final String pathToExportFile;
  late final SettingsYaml settings;

  // ignore: discarded_futures
  void save() => waitForEx(settings.save());

  bool get hasToken => settings.validString(onepubTokenKey);
  String get onepubToken => settings.asString(onepubTokenKey);
  set onepubToken(String token) => settings[onepubTokenKey] = token;
}
