#! /usr/bin/env dcli
/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'package:onepub/src/entry_point.dart';
import 'package:onepub/src/global_args.dart';

void main(List<String> arguments) {
  entrypoint(arguments, CommandSet.OPUB, 'onepub');
}
