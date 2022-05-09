#! /usr/bin/env dcli

import 'package:dcli/dcli.dart';

import 'global_args.dart';
import 'onepub_paths.dart';
import 'onepub_settings.dart';
import 'util/config.dart';
import 'version/version.g.dart';

/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

void entrypoint(List<String> args) {
  final parsedArgs = ParsedArgs.withArgs(args);
  install(dev: parsedArgs.results['dev'] as bool);
  parsedArgs.run();
}

void install({required bool dev}) {
  if (!exists(OnePubPaths().pathToSettingsDir)) {
    createDir(OnePubPaths().pathToSettingsDir, recursive: true);
  }

  if (!exists(OnePubSettings.pathToSettings)) {
    OnePubSettings.pathToSettings.write('version: 1');
  }

  OnePubSettings.load();
  if (OnePubSettings().onepubUrl == null ||
      OnePubSettings().onepubUrl!.isEmpty) {
    OnePubSettings.load();
    ConfigCommand().config(dev: dev);

    print(orange('Installed OnePub version: $packageVersion.'));
  }
}
