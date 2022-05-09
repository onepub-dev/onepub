#! /usr/bin/env dcli
/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'global_args.dart';

void entrypoint(List<String> args) {
  ParsedArgs.withArgs(args).run();
}
