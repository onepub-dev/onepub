/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';
import 'package:onepub/src/pub/command.dart';

import 'commands/add_dependency.dart';
import 'commands/doctor.dart';
import 'commands/export.dart';
import 'commands/import.dart';
import 'commands/login.dart';
import 'commands/logout.dart';
import 'commands/private.dart';
import 'commands/pub.dart';
import 'exceptions.dart';
import 'util/log.dart';
import 'version/version.g.dart';

///
class ParsedArgs {
  factory ParsedArgs() => _self;

  ///
  ParsedArgs.withArgs(this.args) : runner = CommandRunner<void>('onepub', '''

${orange('OnePub cli tools')}

You can alter the config by running 'onepub config' or by modifying ${join(HOME, '.onepub', 'onepub.yaml')}''') {
    _self = this;
    build();
    parse();
  }

  static late ParsedArgs _self;

  late final ArgResults results;

  List<String> args;

  CommandRunner<void> runner;

  late final bool colour;
  late final bool quiet;

  late final bool secureMode;
  late final bool useLogfile;
  late final String logfile;

  ///

  void build() {
    runner.argParser
        .addFlag('debug', abbr: 'd', help: 'Enable versbose logging');
    runner.argParser
        .addFlag('version', help: 'Displays the onepub version no. and exits.');

    runner.argParser.addFlag('dev',
        hide: true,
        help: 'Allows for configuration of localhost for '
            'use in a development environment.');

    runner
      ..addCommand(DoctorCommand())
      ..addCommand(LoginCommand())
      ..addCommand(LogoutCommand())
      ..addCommand(PubCommand2())
      ..addCommand(ImportCommand())
      ..addCommand(ExportCommand())
      ..addCommand(AddDependencyCommand())
      ..addCommand(PrivateCommand());
  }

  void parse() {
    results = runner.argParser.parse(args);
    Settings().setVerbose(enabled: results['debug'] as bool);

    final version = results['version'] as bool == true;
    if (version == true) {
      print('onepub $packageVersion');
      exit(0);
    }
  }

  void run() {
    try {
      waitForEx(runner.run(args));
    } on FormatException catch (e) {
      logerr(red(e.message));
      // this is an Exception (generally from the server, not a usage problem)
      //showUsage();
    } on UsageException catch (e) {
      logerr(red(e.message));
      showUsage();
      // ignore: avoid_catches_without_on_clauses
    } on ExitException catch (e) {
      printerr(e.message);
      exit(e.exitCode);
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      logerr(red(e.toString()));
    }
  }

  void showUsage() {
    runner.printUsage();
    exit(1);
  }
}
