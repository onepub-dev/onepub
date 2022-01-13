import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';
import '../exceptions.dart';

import '../onepub_settings.dart';
import '../util/send_command.dart';

/// onepub Logout <email>
///     - if the user doesn't exists sends them an Logout.
class LogoutCommand extends Command<void> {
  ///
  LogoutCommand();

  @override
  String get description => 'Logs a person to join onepub.dev.';

  @override
  String get name => 'logout';

  @override
  Future<void> run() async {
    loadSettings();

    if (argResults!.rest.isNotEmpty) {
      throw ExitException(exitCode: -1, message: red('''
The logout command takes no arguments. Found ${argResults!.rest.join(',')}.
'''));
    }

   

    await getCommand(
        endpoint: '/api/logout');

    'dart pub token remove ${OnepubSettings.onepubWebUrl}'.run;
  }
}
