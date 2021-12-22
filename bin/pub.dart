#! /usr/bin/env dcli

import 'dart:io';

import 'package:dcli/dcli.dart';

void main(List<String> arguments) {
  final pubspec = DartProject.fromPath('.').pubSpec;
  final isFlutter = pubspec.dependencies.containsKey('flutter');

  if (isFlutter) {
    if (which('flutter').notfound) {
      printerr(red('Add flutter to your PATH and try again.'));
      exit(1);
    }
    startFromArgs(
      'flutter',
      ['pub', ...arguments],
      nothrow: true,
      progress: Progress.print(),
    );
  } else {
    if (which('dart').notfound) {
      printerr(red('Add dart to your PATH and try again.'));
      exit(1);
    }
    DartSdk().runPub(args: arguments, nothrow: true);
  }
}
