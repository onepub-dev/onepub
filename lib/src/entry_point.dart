#! /usr/bin/env dart

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dcli_terminal/dcli_terminal.dart';
import 'package:scope/scope.dart';

import 'exceptions.dart';
import 'my_runner.dart';
import 'onepub_settings.dart';
import 'util/log.dart' as ulog;
import 'util/printerr.dart';
import 'version/version.g.dart';

/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

/// Used by unit tests to alter the working directory a command runs in.
ScopeKey<String> unitTestWorkingDirectoryKey =
    ScopeKey<String>('WorkingDirectory');

/// The [args] list should contain the command to be run
/// followed by the arguments to be passed to the command.
///
/// The [executableName] is used when displaying help.
Future<void> entrypoint(
  List<String> args,
  CommandSet commandSet,
  String executableName,
) async {
  try {
    final runner = MyRunner(args, executableName, _description, commandSet);
    try {
      printPreamble();
      await runner.init();
      await runner.run(args);
    } on FormatException catch (e) {
      printerr(e.message);
      // this is an Exception (generally from the server, not a usage problem)
      //showUsage();
    } on UsageException catch (e) {
      printerr(e.message);
      printerr('');
      printerr(e.usage);
    }
  } on ExitException catch (e) {
    printerr(e.message);
    // final firstLine = e.message.split('\n').first;
    // final rest = e.message.split('\n').skip(1).join('\n');
    // printerr(red('Error: $firstLine'));
    // printerr('');
    // printerr(rest);
    exit(e.exitCode);
    // ignore: avoid_catches_without_on_clauses
  } catch (e, s) {
    ulog.logerr('$e\n$s');
  }
}

void showUsage(MyRunner runner) {
  runner.printUsage();
  exit(1);
}

String get _description => orange('OnePub CLI tools.');

void printPreamble() {
  print(orange('OnePub version: $packageVersion '));

  print('');

  OnePubSettings().nonStandardUrlWarning();
}
