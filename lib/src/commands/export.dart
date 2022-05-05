import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';
import 'package:validators2/validators.dart';

import '../exceptions.dart';
import '../onepub_paths.dart';
import '../onepub_settings.dart';
import '../util/one_pub_token_store.dart';
import '../util/send_command.dart';
import '../util/token_export_file.dart';

///
class ExportCommand extends Command<void> {
  ///
  ExportCommand() {
    argParser
      ..addFlag('file', abbr: 'f', help: 'Save the OnePub token to a file')
      ..addOption('user',
          abbr: 'u',
          help: 'Export the token of a CICD member.',
          valueHelp: 'email address of a CI/CD Member');
  }

  @override
  String get description =>
      'Exports your onepub token or a designated CI/CD user.';

  @override
  String get name => 'export';

  @override
  Future<void> run() async {
    await export();
  }

  ///
  Future<void> export() async {
    OnePubSettings.load();
    if (!exists(OnePubPaths().pathToSettingsDir)) {
      createDir(OnePubPaths().pathToSettingsDir, recursive: true);
    }
    final file = argResults!['file'] as bool;
    final user = argResults!['user'] as String?;

    if (!OnePubTokenStore().isLoggedIn) {
      throw ExitException(
          exitCode: 1, message: "You must run 'onepub login' first.");
    }

    final String onepubToken;

    if (user != null) {
      if (!isEmail(user)) {
        throw ExitException(
            exitCode: 1,
            message: 'The supplied user must be a valid email address. '
                'Found $user');
      }
      final response = await sendCommand(command: 'member/token/$user');
      if (response.success) {
        final token = response.data['onepubToken'];
        if (token == null) {
          throw ArgumentError('No token was returned');
        }
        onepubToken = response.data['onepubToken']! as String;
      } else {
        throw ExitException(
            exitCode: 1, message: response.data['message']! as String);
      }
    } else {
      onepubToken = OnePubTokenStore().fetch();
    }
    print(orange(
        'Exporting OnePub token for ${OnePubSettings().organisationName}.'));

    if (file) {
      final exportFile =
          TokenExportFile(join(pwd, TokenExportFile.exportFilename))
            ..onepubToken = onepubToken
            ..save();

      print('''

Saved credentials to: ${truepath(exportFile.pathToExportFile)}.

Copy the onepub.token.yaml to your CI/CD environment and run:
    
    onepub import <path to credentials>

''');
    } else {
      print('');
      print('Add the following environment variable to your CI/CD secrets.');
      print('');
      print('ONEPUB_SECRET=$onepubToken');
      print('');
      return;
    }
  }
}
