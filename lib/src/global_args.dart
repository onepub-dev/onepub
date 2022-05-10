/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart' hide log;
import 'package:onepub/src/pub/command.dart';
import 'package:onepub/src/pub/log.dart';
import 'package:onepub/src/util/config.dart';

import 'commands/add_dependency.dart';
import 'commands/doctor.dart';
import 'commands/export.dart';

import 'commands/import.dart';
import 'commands/login.dart';
import 'commands/logout.dart';
import 'commands/private.dart';

import 'exceptions.dart';
import 'onepub_paths.dart';
import 'onepub_settings.dart';
import 'pub/command/add.dart';

import 'pub/command/cache.dart';
import 'pub/command/deps.dart';
import 'pub/command/downgrade.dart';
import 'pub/command/get.dart';
import 'pub/command/global.dart';
import 'pub/command/lish.dart';
import 'pub/command/login.dart';
import 'pub/command/logout.dart';
import 'pub/command/outdated.dart';
import 'pub/command/remove.dart';
import 'pub/command/run.dart';
import 'pub/command/token.dart';
import 'pub/command/upgrade.dart';
import 'pub/command/uploader.dart';
import 'pub/command/version.dart';
import 'pub/io.dart';
import 'pub/log.dart' as plog;

import 'util/log.dart' as ulog;
import 'version/version.g.dart';

///
///
class MyRunner extends CommandRunner<int> implements PubTopLevel {
  MyRunner(this.args, String executableName, String description,
      CommandSet commandSet)
      : super(executableName, description) {
    if (commandSet == CommandSet.ONEPUB) {
      argParser.addFlag('debug', abbr: 'd', help: 'Enable versbose logging');
      argParser.addFlag('version',
          help: 'Displays the onepub version no. and exits.');

      argParser.addFlag('dev',
          hide: true,
          help: 'Allows for configuration of localhost for '
              'use in a development environment.');
      addCommand(DoctorCommand());
      addCommand(OnePubLoginCommand());
      addCommand(OnePubLogoutCommand());
      addCommand(ImportCommand());
      addCommand(ExportCommand());
      addCommand(AddDependencyCommand());
      addCommand(PrivateCommand());

      results = argParser.parse(args);
      Settings().setVerbose(enabled: results['debug'] as bool);

      final version = results['version'] as bool == true;
      if (version == true) {
        print('onepub $packageVersion');
        exit(0);
      }

      install(dev: results['dev'] as bool);
    }

    if (commandSet == CommandSet.OPUB) {
      argParser.addFlag('version',
          negatable: false, help: 'Print pub version.');
      argParser.addFlag('trace',
          help: 'Print debugging information when an error occurs.');
      argParser
          .addOption('verbosity', help: 'Control output verbosity.', allowed: [
        'error',
        'warning',
        'normal',
        'io',
        'solver',
        'all'
      ], allowedHelp: {
        'error': 'Show only errors.',
        'warning': 'Show only errors and warnings.',
        'normal': 'Show errors, warnings, and user messages.',
        'io': 'Also show IO operations.',
        'solver': 'Show steps during version resolution.',
        'all': 'Show all output including internal tracing messages.'
      });
      argParser.addFlag('verbose',
          abbr: 'v', negatable: false, help: 'Shortcut for "--verbosity=all".');
      argParser.addOption(
        'directory',
        abbr: 'C',
        help: 'Run the subcommand in the directory<dir>.',
        defaultsTo: '.',
        valueHelp: 'dir',
      );
      addCommand(LishCommand());
      addCommand(GetCommand());
      addCommand(AddCommand());

      addCommand(CacheCommand());
      addCommand(DepsCommand());
      addCommand(DowngradeCommand());
      addCommand(GlobalCommand());

      addCommand(OutdatedCommand());
      addCommand(RemoveCommand());
      addCommand(RunCommand());

      addCommand(UpgradeCommand());
      addCommand(UploaderCommand());
      addCommand(VersionCommand());
      addCommand(LoginCommand());
      addCommand(LogoutCommand());

      addCommand(TokenCommand());
      results = argParser.parse(args);
    }
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
        OnePubSettings().onepubUrl!.isEmpty ||
        dev) {
      OnePubSettings.load();
      ConfigCommand().config(dev: dev);

      print(orange('Installed OnePub version: $packageVersion.'));
    }

    if (exists(ConfigCommand.testingFlagPath)) {
      if (OnePubSettings().onepubUrl == OnePubSettings.defaultOnePubUrl) {
        print(('This system is configured for testing, but is also configured'
            ' for the production URL. If you need to change this, then delete '
            '${ConfigCommand.testingFlagPath} or use the --dev option to '
            'change the URL'));
        exit(1);
      }
    }
  }

  List<String> args;
  late ArgResults results;

  @override
  ArgResults get argResults => results;

  @override
  String? get directory => argResults['directory'];

  @override
  bool get captureStackChains {
    return argResults['trace'] ||
        argResults['verbose'] ||
        argResults['verbosity'] == 'all';
  }

  @override
  Verbosity get verbosity {
    switch (argResults['verbosity']) {
      case 'error':
        return plog.Verbosity.error;
      case 'warning':
        return plog.Verbosity.warning;
      case 'normal':
        return plog.Verbosity.normal;
      case 'io':
        return plog.Verbosity.io;
      case 'solver':
        return plog.Verbosity.solver;
      case 'all':
        return plog.Verbosity.all;
      default:
        // No specific verbosity given, so check for the shortcut.
        if (argResults['verbose']) return plog.Verbosity.all;
        if (runningFromTest) return plog.Verbosity.testing;
        return plog.Verbosity.normal;
    }
  }

  @override
  bool get trace => argResults['trace'];
}

enum CommandSet { OPUB, ONEPUB }

class ParsedArgs {
  factory ParsedArgs() => _self;

  ///
  ParsedArgs.withArgs(this.args, CommandSet commandSet, String program)
      : runner = MyRunner(
            args,
            program,
            '''

${orange('OnePub cli tools')}

You can alter the config by running 'onepub config' or by modifying ${join(HOME, '.onepub', 'onepub.yaml')}''',
            commandSet) {
    _self = this;
  }

  static late ParsedArgs _self;

  late final ArgResults results;

  List<String> args;

  CommandRunner<int> runner;

  late final bool colour;
  late final bool quiet;

  late final bool secureMode;
  late final bool useLogfile;
  late final String logfile;

  ///

  int run() {
    try {
      waitForEx(runner.run(args));
    } on FormatException catch (e) {
      ulog.logerr((e.message));
      // this is an Exception (generally from the server, not a usage problem)
      //showUsage();
    } on UsageException catch (e) {
      ulog.logerr((e.message));
      showUsage();
      // ignore: avoid_catches_without_on_clauses
    } on ExitException catch (e) {
      printerr(e.message);
      exit(e.exitCode);
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      ulog.logerr((e.toString()));
    }
    return 0;
  }

  void showUsage() {
    runner.printUsage();
    exit(1);
  }
}
