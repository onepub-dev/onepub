#! /usr/bin/env dcli

import 'global_args.dart';

/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

void entrypoint(List<String> args, CommandSet commandSet, String program) {
  final parsedArgs = ParsedArgs.withArgs(args, commandSet, program);

  parsedArgs.run();
}
