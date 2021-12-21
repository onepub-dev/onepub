#! /usr/bin/env dcli

import 'package:dcli/dcli.dart';

void main(List<String> arguments) {
  if (which('flutter').found) {
    final progress = Progress.print();
    startFromArgs(
      'flutter',
      ['pub', ...arguments],
      nothrow: true,
      progress: progress,
    );
  } else {
    DartSdk().runPub(args: arguments, nothrow: true);
  }
}
