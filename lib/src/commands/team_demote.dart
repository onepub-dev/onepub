import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';
import '../exceptions.dart';

import '../onepub_settings.dart';
import '../util/send_command.dart';

/// onepub team demote  <team> <member email>
class TeamDemoteCommand extends Command<void> {
  ///
  TeamDemoteCommand();

  @override
  String get description => 'Demotes a team leader to a team member';

  @override
  String get name => 'demote';

  @override
  Future<void> run() async {
    loadSettings();

    if (argResults!.rest.length != 1) {
      throw ExitException(
          exitCode: -1,
          message: red('The team demote command takes two arguments '
              '<team> <member email>'));
    }

    final team = argResults!.rest[0];

    await sendCommand(endpoint: '/api/team/demote/$team');
  }
}
