#! /usr/bin/env dcli

import 'package:dcli/dcli.dart';

void main(List<String> arguments) {
  if (which('flutter').found) {
    startFromArgs(
      'flutter',
      ['pub', ...arguments],
      nothrow: true,
      progress: Progress.print(),
    );
  } else {
    DartSdk().runPub(args: arguments, nothrow: true);
  }
}
