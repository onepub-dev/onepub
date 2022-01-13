import 'package:dcli/dcli.dart';

void log(String message) {
  final _message = Ansi.strip(message);
  _logout(green(_message));
}

void loginfo(String message) {
  final _message = Ansi.strip(message);
  _logout(blue(_message));
}

void logwarn(String message) {
  final _message = Ansi.strip(message);
  _logerr(orange(_message));
}

void logerr(String message) {
  final _message = Ansi.strip(message);
  _logerr(red(_message));
}

void _logout(String message) {
  final args = ParsedArgs();

  var _message = message;
  if (args.colour == false) {
    _message = Ansi.strip(message);
  }

  if (args.useLogfile) {
    args.logfile.append(_message);
  } else {
    print(_message);
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

  var _message = message;
  if (args.colour == false) {
    _message = Ansi.strip(message);
  }

  if (args.useLogfile) {
    args.logfile.append(_message);
  } else {
    printerr(_message);
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
