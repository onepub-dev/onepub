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
      throw ExitException(exitCode: 1, message: red('''
The logout command takes no arguments. Found ${argResults!.rest.join(',')}.
'''));
    }

    final results = await sendCommand(command: 'logout');

    if (!results.success) {
      throw ExitException(
          exitCode: 1, message: results.data['message']! as String);
    }

    final progress = 'dart pub token remove ${OnepubSettings().onepubWebUrl}'
        .start(nothrow: true, progress: Progress.capture());

    /// 65 means no token was found so we were probably already logged out.
    if (progress.exitCode != 0 && progress.exitCode != 65) {
      print(progress.toParagraph());
      return;
    }
    print(green('You have been logged out.'));
  }
}
