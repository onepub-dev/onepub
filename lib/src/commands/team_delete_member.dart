import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';
import '../exceptions.dart';

import '../onepub_settings.dart';
import '../util/send_command.dart';

/// onepub team create  <team>
class TeamDeleteMemberCommand extends Command<void> {
  ///
  TeamDeleteMemberCommand();

  @override
  String get description => 'Deletes a member from a team';

  @override
  String get name => 'delete';

  @override
  Future<void> run() async {
    loadSettings();

    if (argResults!.rest.length != 1) {
      throw ExitException(
          exitCode: -1,
          message:
              red('The team delete command takes a single argument <team>'));
    }

    final team = argResults!.rest[0];

    await getCommand(endpoint: '/api/team/delete/$team');
  }
}
