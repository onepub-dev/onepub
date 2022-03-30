import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';
import '../exceptions.dart';

import '../onepub_settings.dart';
import '../util/one_pub_token_store.dart';
import '../util/send_command.dart';

/// onepub Logout <email>
///     - if the user doesn't exists sends them an Logout.
class LogoutCommand extends Command<void> {
  ///
  LogoutCommand();

  @override
  String get description => 'Log out of OnePub CLI on all your devices.';

  @override
  String get name => 'logout';

  @override
  Future<void> run() async {
    loadSettings();

    if (argResults!.rest.isNotEmpty) {
      throw ExitException(exitCode: 1, message: red('''
The logout command takes no arguments. Found ${argResults!.rest.join(',')}.
'''));
    }

    final results = await sendCommand(command: '/member/logout');

    if (!results.success) {
      throw ExitException(
          exitCode: 1, message: results.data['message']! as String);
    }

    OnePubTokenStore().clearOldTokens();

    print(green('You have been logged out of the OnePub CLI for '
        '${OnePubSettings().organisationName} on all your devices.'));
  }
}
