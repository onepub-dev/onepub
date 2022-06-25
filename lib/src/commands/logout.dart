/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';
import '../exceptions.dart';

import '../onepub_settings.dart';
import '../util/one_pub_token_store.dart';
import '../util/send_command.dart';

/// onepub Logout <email>
///     - if the user doesn't exists sends them an Logout.
class OnePubLogoutCommand extends Command<int> {
  ///
  OnePubLogoutCommand();

  @override
  String get description => 'Log out of OnePub CLI on all your devices.';

  @override
  String get name => 'logout';

  @override
  Future<int> run() async {
    loadSettings();

    if (argResults!.rest.isNotEmpty) {
      throw ExitException(exitCode: 1, message: red('''
The logout command takes no arguments. Found ${argResults!.rest.join(',')}.
'''));
    }

    if (OnePubTokenStore().isLoggedIn) {
      final results = await sendCommand(command: '/member/logout');

      OnePubTokenStore().clearOldTokens();

      if (!results.success) {
        final message = results.data['message']! as String;
        if (!(message.startsWith('Your token is no longer valid') ||
            message.startsWith('You must be logged in to run this command.'))) {
          throw ExitException(exitCode: 1, message: message);
        }
      }
      print(green('You have been logged out of the OnePub CLI for '
          '${OnePubSettings().organisationName} on all your devices.'));
    } else {
      OnePubTokenStore().clearOldTokens();
      print(orange('You are already logged out.'));
    }

    return 0;
  }
}
