/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';

import 'pub/add_dep.dart';
import 'pub/global.dart';
import 'pub/private.dart';

/// Provides the abilty to work with global packages that are hosted
/// as private packages on OnePub
class PubCommand extends Command<int> {
  ///
  PubCommand() : super() {
    addSubcommand(GlobalCommand());
    addSubcommand(AddPrivateCommand());
    addSubcommand(PrivateCommand());
  }
  @override
  String get name => 'pub';
  @override
  String get description => blue('Work with packages.');
}
