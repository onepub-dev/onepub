/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'package:args/command_runner.dart';

import 'global.dart';

/// Provides the abilty to work with global packages that are hosted
/// as private packages on OnePub
class PubCommand extends Command<int> {
  @override
  String get name => 'pub';
  @override
  String get description => 'Work with packages.';

  ///
  PubCommand() : super() {
    addSubcommand(GlobalCommand());
  }
}
