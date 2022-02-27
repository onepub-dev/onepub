import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';

import '../onepub_paths.dart';
import '../onepub_settings.dart';
import '../version/version.g.dart';
import 'team_add_member.dart';
import 'team_delete_member.dart';

/// provides actions on a team
///
/// onepub team create  <team>
/// onepub team <team> add <member email>
///     - if the user doesn't exists sends them an invite.
/// onepub team <team> delete <member email>
/// onepub team <team> promote <member email> - makes them a team leader
/// onepub team <team> demote <member email> - removes their team leader status.
///
class TeamMemberCommand extends Command<void> {
  ///
  TeamMemberCommand() {
    addSubcommand(TeamAddMemberCommand());
    addSubcommand(TeamDeleteMemberCommand());
  }

  @override
  String get description => 'Manages team members.';

  @override
  String get name => 'member';

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
Register with or accept your invite to OnePub at http://onepub.dev/register
Then run: 
  onepub auth

You can then use `opub` in place of `dart pub` or `flutter pub`.

Alternatively you can create the PUB_HOSTED_URL environment variable and continue to use dart pub or flutter pub.
'''));

    print(green('Install of OnePub complete.'));
  }
}
