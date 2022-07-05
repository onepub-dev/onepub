#! /usr/bin/env dcli
/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'package:dcli/dcli.dart';
import 'package:onepub/src/entry_point.dart';
import 'package:onepub/src/my_runner.dart';
import 'package:onepub/src/version/version.g.dart';

void main(List<String> arguments) async {
  print(orange('OnePub version: $packageVersion '));

  print('');

  await entrypoint(arguments, CommandSet.ONEPUB, 'onepub');
}
