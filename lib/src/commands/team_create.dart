import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';
import '../exceptions.dart';

import '../onepub_settings.dart';
import '../util/send_command.dart';

/// onepub team create  <team>
class TeamCreateCommand extends Command<void> {
  ///
  TeamCreateCommand();

  @override
  String get description => 'Creates a team';

  @override
  String get name => 'create';

  @override
  Future<void> run() async {
    loadSettings();

    if (argResults!.rest.length != 1) {
      throw ExitException(
          exitCode: -1,
          message:
              red('The team create command takes a single argument <team>'));
    }

    final team = argResults!.rest[0];

    await sendCommand(endpoint: '/api/team/create/$team');
  }
}
