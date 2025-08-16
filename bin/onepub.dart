#! /usr/bin/env dart

/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */
import 'package:onepub/src/entry_point.dart';

Future<void> main(List<String> arguments) async {
  await entrypoint(arguments, 'onepub');
}
