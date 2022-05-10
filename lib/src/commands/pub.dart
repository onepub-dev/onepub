/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'dart:async';

import 'package:args/command_runner.dart';

import '../pub/command_runner.dart';

/// onepub Logout <email>
///     - if the user doesn't exists sends them an Logout.
class PubCommand2 extends Command<void> {
  ///
  PubCommand2();

  @override
  String get description => 'Publish.';

  @override
  String get name => 'pub';

  @override
  Future<void> run() async {
    PubCommandRunner().run(<String>['publish']);
  }
}
