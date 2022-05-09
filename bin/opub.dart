#! /usr/bin/env dcli
/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'dart:io';

import 'package:dcli/dcli.dart';
import 'package:onepub/src/onepub_settings.dart';

void main(List<String> arguments) {
  final dartProject = DartProject.findProject('.');
  if (dartProject == null) {
    printerr(
        red('The current directory ${truepath(pwd)} is not in a dart project'));
    exit(1);
  }
  final pubspec = dartProject.pubSpec;
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

    withEnvironment(() {
      DartSdk().runPub(args: arguments, nothrow: true);
    }, environment: {
      OnePubSettings.pubHostedUrlKey: OnePubSettings().onepubApiUrl
    });
  }
}
