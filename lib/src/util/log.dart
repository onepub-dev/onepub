/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */
import 'package:dcli_terminal/dcli_terminal.dart';

import 'printerr.dart';
import 'string_extension.dart';

void log(String message) {
  final message0 = Ansi.strip(message);
  _logout(green(message0));
}

void loginfo(String message) {
  final message0 = Ansi.strip(message);
  _logout(blue(message0));
}

void logwarn(String message) {
  final message0 = Ansi.strip(message);
  _logerr(orange(message0));
}

void logerr(String message) {
  final message0 = Ansi.strip(message);
  _logerr(red(message0));
}

void _logout(String message) {
  final args = ParsedArgs();

  var message0 = message;
  if (!args.colour) {
    message0 = Ansi.strip(message);
  }

  if (args.useLogfile) {
    args.logfile.append(message0);
  } else {
    print(message0);
  }
}

class ParsedArgs {
  bool get colour => true;
  bool get useLogfile => false;
  String get logfile => '';

  bool get quiet => false;
}

void _logerr(String message) {
  final args = ParsedArgs();

  var message0 = message;
  if (!args.colour) {
    message0 = Ansi.strip(message);
  }

  if (args.useLogfile) {
    args.logfile.append(message0);
  } else {
    printerr(message0);
  }
}

void overwriteLine(String message) {
  final args = ParsedArgs();
  if (!args.quiet) {
    if (args.useLogfile) {
      log(message);
    } else {
      Terminal().overwriteLine(message);
    }
  }
}
