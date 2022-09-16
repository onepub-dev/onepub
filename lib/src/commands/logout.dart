/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */
import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';
import '../api/api.dart';
import '../exceptions.dart';

import '../onepub_settings.dart';
import '../util/one_pub_token_store.dart';

/// onepub Logout <email>
///     - if the user doesn't exists sends them an Logout.
class OnePubLogoutCommand extends Command<int> {
  ///
  OnePubLogoutCommand();

  @override
  String get description => blue('Log out of OnePub CLI on all your devices.');

  @override
  String get name => 'logout';

  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      throw ExitException(exitCode: 1, message: red('''
The logout command takes no arguments. Found ${argResults!.rest.join(',')}.
'''));
    }

    if (OnePubTokenStore().isLoggedIn) {
      await API().checkVersion();
      final response = await API().logout();
      OnePubTokenStore().clearOldTokens();

      if (!response.success) {
        throw ExitException(exitCode: 1, message: response.errorMessage);
      }

      print(green('You have been logged out of the OnePub CLI for '
          '${OnePubSettings.use.organisationName} '
          'on all your devices.'));
    } else {
      OnePubTokenStore().clearOldTokens();
      print(orange('You are already logged out.'));
    }

    return 0;
  }
}
