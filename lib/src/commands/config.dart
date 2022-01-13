import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';
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
            'use in a development enviornment.');
  }

  @override
  String get description => 'Configures Onepub.';

  @override
  String get name => 'config';

  @override
  void run() {
    if (!exists(OnepubSettings.pathToSettings)) {
      logerr(red('''You must run 'Onepub install' first.'''));
      exit(1);
    }
    OnepubSettings.load();

    final dev = argResults!['dev'] as bool;

    config(dev: dev);
  }

  ///
  void config({required bool dev}) {
    print('Configure Onepub');
    promptForConfig(dev: dev);
  }

  void promptForConfig({required bool dev}) {
    var port = OnepubSettings().port;
    var host = OnepubSettings().host;

    if (dev) {
      host = ask('Onepub host:',
          validator: Ask.any([
            Ask.fqdn,
            Ask.ipAddress(),
            Ask.inList(['localhost'])
          ]),
          defaultValue: host);
      port = ask('Onepub port:', validator: Ask.integer, defaultValue: port);
    }

    OnepubSettings().port = port;
    OnepubSettings().host = host;
    OnepubSettings().save();
  }
}
