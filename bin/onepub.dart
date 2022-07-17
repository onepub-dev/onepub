#! /usr/bin/env dcli

/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */
import 'package:dcli/dcli.dart';
import 'package:onepub/src/entry_point.dart';
import 'package:onepub/src/my_runner.dart';
import 'package:onepub/src/version/version.g.dart';

void main(List<String> arguments) async {
  print(orange('OnePub version: $packageVersion '));

  print('');

  await entrypoint(arguments, CommandSet.onepub, 'onepub');
}
