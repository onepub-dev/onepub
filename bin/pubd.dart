#! /usr/bin/env dcli

import 'dart:io';

import 'package:dcli/dcli.dart';

void main(List<String> arguments) {
  if (which('dart').notfound) {
    printerr(red('Dart was not found on your path.'));
    exit(1);
  }

  DartSdk().runPub(args: arguments, nothrow: true);
}
