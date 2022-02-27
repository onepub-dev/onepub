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
    var url = OnePubSettings.defaultOnePubApiUrl;
    if (dev) {
      url =
          ask('OnePub Api URL:', validator: UrlValidator(), defaultValue: url);
    }

    OnePubSettings().onepubApiUrl = url;
    OnePubSettings().save();
  }
}

class UrlValidator extends AskValidator {
  @override
  String validate(String line) {
    final finalLine = line.trim().toLowerCase();

    if (!isFQDN(finalLine)) {
      throw AskValidatorException(red('Invalid FQDN.'));
    }
    return finalLine;
  }
}
