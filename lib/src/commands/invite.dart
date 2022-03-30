import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';
import '../exceptions.dart';

import '../onepub_settings.dart';
import '../util/send_command.dart';

/// onepub invite <email>
///     - if the user doesn't exists sends them an invite.
class InviteCommand extends Command<void> {
  ///
  InviteCommand();

  @override
  String get description =>
      'Invites a person to join ${OnePubSettings.onepubHostName}.';

  @override
  String get name => 'add';

  @override
  Future<void> run() async {
    loadSettings();

    if (argResults!.rest.length != 1) {
      throw ExitException(exitCode: -1, message: red('''
The team add command takes two arguments:
onepub team add <team> <email>
'''));
    }

    final team = argResults!.rest[0];

    await sendCommand(command: 'team/Add/$team');
  }
}
