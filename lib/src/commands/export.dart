/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */
import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';
import 'package:validators2/validators.dart';

import '../api/api.dart';
import '../exceptions.dart';
import '../onepub_settings.dart';
import '../util/one_pub_token_store.dart';
import '../util/token_export_file.dart';

///
class ExportCommand extends Command<int> {
  ///
  ExportCommand() {
    argParser
      ..addFlag('file', abbr: 'f', help: '''
Save the OnePub token to a file.
Pass in a filename or leave blank to use the default filename.''')
      ..addOption('user',
          abbr: 'u',
          help: 'Export the token of a CICD member rather than your token.',
          valueHelp: 'email address of a CI/CD OnePub Member');
  }

  @override
  String get description => blue(
      'Exports your OnePub token or the token of a designated CI/CD user.');

  @override
  String get name => 'export';

  @override
  Future<int> run() async {
    await export();
    return 0;
  }

  ///
  Future<void> export() async {
    await withSettings(() async {
      // if (!exists(OnePubSettings.use.pathToSettingsDir)) {
      //   createDir(OnePubSettings.use.pathToSettingsDir, recursive: true);
      // }
      final file = argResults!['file'] as bool;
      final user = argResults!['user'] as String?;

      if (!OnePubTokenStore().isLoggedIn) {
       throw ExitException(exitCode: 1, message: '''
You must be logged in to run this command.
run: onepub login
  ''');
      }

      final String onepubToken;

      if (user != null) {
        if (!isEmail(user)) {
          throw ExitException(
              exitCode: 1,
              message: 'The supplied user must be a valid email address. '
                  'Found $user');
        }
        final response = waitForEx(API().fetchMemberToken(user));

        if (response.success) {
          onepubToken = response.token!;
        } else {
          throw ExitException(exitCode: 1, message: response.errorMessage!);
        }
      } else {
        onepubToken = OnePubTokenStore().fetch();
      }
      print(orange('Exporting OnePub token for '
          '${OnePubSettings.use.organisationName}.'));

      if (file) {
        var pathToFile = TokenExportFile.exportFilename;
        if (argResults!.rest.length == 1) {
          pathToFile = argResults!.rest[0];
        } else if (argResults!.rest.isNotEmpty) {
          throw ExitException(
              exitCode: 1,
              message: 'You may only pass one argument to --file.');
        }

        final exportFile = TokenExportFile(pathToFile)
          ..onepubToken = onepubToken
          ..save();

        print('''

Saved OnePub token to: ${truepath(exportFile.pathToExportFile)}.

Copy the ${exportFile.pathToExportFile} to your CI/CD environment and run:
    
    onepub import --file <path to OnePub token file>

''');
      } else {
        print('');
        print('Add the following environment variable to your CI/CD secrets.');
        print('');
        print('ONEPUB_TOKEN=$onepubToken');
        print('');
        return;
      }
    });
  }
}
