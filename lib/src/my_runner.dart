/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:dcli_core/dcli_core.dart';

import 'commands/doctor.dart';
import 'commands/export.dart';
import 'commands/import.dart';
import 'commands/login.dart';
import 'commands/logout.dart';
import 'commands/pub.dart' as onepub;
import 'exceptions.dart';
import 'onepub_settings.dart';

///
///
class MyRunner extends CommandRunner<int> {
  List<String> args;

  late ArgResults results;

  MyRunner(this.args, String executableName, String description)
      : super(executableName, description) {
    try {
      onepubCommands();
    } on FormatException catch (e) {
      throw ExitException(exitCode: 1, message: e.message);
    }
  }

  Future<void> init() async {
    addColorFlag(argParser);

    results = argParser.parse(args);

    await Settings().setVerbose(enabled: results['debug'] as bool);

    final version = results['version'] as bool;
    if (version) {
      // no output required as the startup logic already prints the version.
      exit(0);
    }

    await OnePubSettings.install(dev: results['dev'] as bool);
  }

  void onepubCommands() {
    argParser
      ..addFlag('debug',
          negatable: false, abbr: 'd', help: 'Enable verbose logging')
      ..addFlag('version',
          negatable: false, help: 'Displays the onepub version no. and exits.')
      ..addFlag('dev',
          hide: true,
          negatable: false,
          help: 'Allows for configuration of localhost for '
              'use in a development environment.');

    addCommand(DoctorCommand());
    addCommand(OnePubLoginCommand());
    addCommand(OnePubLogoutCommand());
    addCommand(ImportCommand());
    addCommand(ExportCommand());
    addCommand(onepub.PubCommand());
  }

  // @override
  // String get directory {
  //   if (results.options.contains('directory') &&
  //       results.wasParsed('directory')) {
  //     return results['directory'] as String;
  //   }

  //   /// if we are in a unit test and directory hasn't been passed
  //   if (Scope.hasScopeKey(unitTestWorkingDirectoryKey)) {
  //     return Scope.use(unitTestWorkingDirectoryKey);
  //   }
  //   //  no working dir
  //   return '';
  // }

  bool get verbose {
    if (!results.options.contains('verbose')) {
      return false;
    }
    return results['verbose'] as bool;
  }

  static void addColorFlag(ArgParser argParser) {
    argParser.addFlag(
      'color',
      help: 'Use colors in terminal output.\n'
          'Defaults to color when connected to a '
          'terminal, and no-color otherwise.',
    );
  }
}
