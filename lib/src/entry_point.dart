#! /usr/bin/env dcli

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';

import 'exceptions.dart';
import 'my_runner.dart';
import 'util/log.dart' as ulog;

/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

Future<void> entrypoint(
    List<String> args, CommandSet commandSet, String program) async {
  try {
    MyRunner runner = MyRunner(args, program, _description, commandSet);
    try {
      runner.init();
      await runner.run(args);
    } on FormatException catch (e) {
      ulog.logerr((e.message));
      // this is an Exception (generally from the server, not a usage problem)
      //showUsage();
    } on UsageException catch (e) {
      ulog.logerr((e.message));
      showUsage(runner);
      // ignore: avoid_catches_without_on_clauses
    }
  } on ExitException catch (e) {
    printerr('${red('Error:')} ${e.message}');
    exit(e.exitCode);
    // ignore: avoid_catches_without_on_clauses
  } catch (e) {
    ulog.logerr((e.toString()));
  }
}

void showUsage(MyRunner runner) {
  runner.printUsage();
  exit(1);
}

String get _description => '''

${orange('OnePub CLI tools')}

You can alter the config by running 'onepub config' or by modifying ${join(HOME, '.onepub', 'onepub.yaml')}''';
