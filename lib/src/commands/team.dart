import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';

import '../onepub_paths.dart';
import '../onepub_settings.dart';
import '../version/version.g.dart';
import 'team_create.dart';
import 'team_delete.dart';
import 'team_demote.dart';
import 'team_member.dart';
import 'team_promote.dart';

/// provides actions on a team
///
/// onepub team create  <team>
/// onepub team <team> add <member email>
///     - if the user doesn't exists sends them an invite.
/// onepub team <team> delete <member email>
/// onepub team <team> promote <member email> - makes them a team leader
/// onepub team <team> demote <member email> - removes their team leader status.
///
class TeamCommand extends Command<void> {
  ///
  TeamCommand() {
    addSubcommand(TeamCreateCommand());
    addSubcommand(TeamDeleteCommand());
    addSubcommand(TeamPremoteCommand());
    addSubcommand(TeamDemoteCommand());
    addSubcommand(TeamMemberCommand());
  }

  @override
  String get description => 'Manages teams.';

  @override
  String get name => 'team';

  @override
  void run() {
    install();
  }

  ///
  void install() {
    if (!exists(OnePubPaths().pathToSettingsDir)) {
      createDir(OnePubPaths().pathToSettingsDir, recursive: true);
    }
    OnePubSettings.load();

    print(orange('Installing OnePub version: $packageVersion.'));

    if (!exists(OnePubPaths().pathToSettingsDir)) {
      createDir(OnePubPaths().pathToSettingsDir, recursive: true);
    }

    print(blue('''
Register with or accept your invite to OnePub at http://${OnePubSettings.onepubHostName}/register
Then run: 
  onepub auth

You can then use `opub` in place of `dart pub` or `flutter pub`.

Alternatively you can create the PUB_HOSTED_URL environment variable and continue to use dart pub or flutter pub.
'''));

    print(green('Install of OnePub complete.'));
  }
}
