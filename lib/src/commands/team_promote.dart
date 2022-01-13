import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';
import '../exceptions.dart';

import '../onepub_settings.dart';
import '../util/send_command.dart';

/// onepub team premote  <team> <member email>
class TeamPremoteCommand extends Command<void> {
  ///
  TeamPremoteCommand();

  @override
  String get description => '''
Promotes a team member to a team leader.
If they are not aready a team member then they are also added as a team member
''';

  @override
  String get name => 'promote';

  @override
  Future<void> run() async {
    loadSettings();

    if (argResults!.rest.length != 2) {
      throw ExitException(
          exitCode: -1,
          message: red('The team promote command takes two arguments '
              '<team> <member email>'));
    }

    final team = argResults!.rest[0];
    final email = argResults!.rest[1];

    await getCommand(endpoint: '/api/team/premote/$team/member/$email');
  }
}
