/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';
import 'package:validators2/validators.dart';
import '../onepub_settings.dart';
import '../util/log.dart';

///
class ConfigCommand extends Command<void> {
  ///
  ConfigCommand() {
    argParser.addFlag('dev',
        abbr: 'd',
        hide: true,
        help: 'Allows for configuration of localhost for '
            'use in a development environment.');
  }

  @override
  String get description => 'Configures OnePub.';

  @override
  String get name => 'config';

  @override
  void run() {
    if (!exists(OnePubSettings.pathToSettings)) {
      logerr(red('''You must run 'OnePub install' first.'''));
      exit(1);
    }
    OnePubSettings.load();

    final dev = argResults!['dev'] as bool;

    config(dev: dev);
  }

  ///
  void config({required bool dev}) {
    print('Configure OnePub');
    promptForConfig(dev: dev);
  }

  void promptForConfig({required bool dev}) {
    var url = OnePubSettings.defaultOnePubUrl;
    if (dev) {
      url = ask('OnePub URL:', validator: UrlValidator(), defaultValue: url);
    }

    OnePubSettings().onepubUrl = url;
    OnePubSettings().save();
  }
}

class UrlValidator extends AskValidator {
  @override
  String validate(String line) {
    final finalLine = line.trim().toLowerCase();

    if (!line.startsWith('https://')) {
      throw AskValidatorException(red('Must start with https://'));
    }
    final fqdn = finalLine.replaceFirst('https://', '');
    if (!isFQDN(fqdn)) {
      throw AskValidatorException(red('Invalid FQDN.'));
    }
    return finalLine;
  }
}
