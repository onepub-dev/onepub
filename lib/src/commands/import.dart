/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';

import '../exceptions.dart';
import '../onepub_settings.dart';
import '../util/one_pub_token_store.dart';
import '../util/send_command.dart';
import '../util/token_export_file.dart';

/// Imports a the onepub token generated by the onepub login process
/// and then addes it
class ImportCommand extends Command<int> {
  ///
  ImportCommand() : super() {
    argParser
      ..addFlag('file',
          abbr: 'f',
          negatable: false,
          help: 'Imports the OnePub credentials from onepub.token.yaml')
      ..addFlag('ask',
          abbr: 'a',
          negatable: false,
          help: 'Prompts the user to enter the ONEPUB_SECRET');
  }

  @override
  String get description => '''
Import onepub token.
Use `onepub export` to obtain the token.

  Ask the user to enter the token:
  onepub import --ask

  Import the token from the ${OnePubSettings.onepubTokenKey} environment variable
  onepub import 

  Import the token from onepub.token.yaml
  onepub import --file [<path to credentials>] ''';

  @override
  String get name => 'import';

  @override
  Future<int> run() async {
    await import();
    return 0;
  }

  ///
  Future<void> import() async {
    OnePubSettings.load();
    final file = argResults!['file'] as bool;
    final ask = argResults!['ask'] as bool;

    if (file && ask) {
      throw ExitException(
          exitCode: -1, message: 'You may not pass --ask and --file');
    }

    final String onepubToken;

    if (ask) {
      onepubToken = fromUser();
    } else if (file) {
      onepubToken = fromFile();
    } else {
      onepubToken = fromSecret();
    }

    // the import is an alternate (from login) form of getting
    // authorised but we have a chicken and egg problem
    // because the [sendCommand] expects the token to be
    // in the token store which it isn't
    // So we paass the auth header directly.
    final headers = <String, String>{};
    headers.addAll({'authorization': onepubToken});

    final response = await sendCommand(
        command: '/organisation/token', authorised: false, headers: headers);
    if (!response.success) {
      throw ExitException(
          exitCode: 1, message: response.data['message']! as String);
    }

    final organisationName = response.data['organisationName']! as String;
    final organisationObfuscatedId = response.data['obfuscatedId']! as String;

    OnePubTokenStore().save(
        onepubToken: onepubToken,
        organisationName: organisationName,
        obfuscatedOrganisationId: organisationObfuscatedId);

    print('${blue('Successfully logged into $organisationName.')}');
  }

  /// pull the secret from onepub.export.yaml
  String fromFile() {
    final String pathToTokenFile;
    if (argResults!.rest.length > 1) {
      throw ExitException(exitCode: 1, message: '''
The onepub import command only takes zero or one arguments. 
Found: ${argResults!.rest.join(',')}''');
    }
    if (argResults!.rest.isEmpty) {
      pathToTokenFile = join(pwd, TokenExportFile.exportFilename);
    } else {
      pathToTokenFile = argResults!.rest[0];
    }

    return TokenExportFile.load(pathToTokenFile).onepubToken;
  }

  /// pull the secret from an env var
  String fromSecret() {
    print(orange(
        'Importing OnePub secret from ${OnePubTokenStore.onepubSecretEnvKey}'));

    print(Platform.environment);

    if (!Env().exists(OnePubTokenStore.onepubSecretEnvKey)) {
      throw ExitException(exitCode: 1, message: '''
    The OnePub environment variable ${OnePubTokenStore.onepubSecretEnvKey} doesn't exist.
    Have you added it to your CI/CD secrets?.''');
    }

    return env[OnePubTokenStore.onepubSecretEnvKey]!;
  }

  String fromUser() {
    return ask('ONEPUB_SECRET:',
        required: true,
        validator: Ask.all([
          Ask.regExp(r'[a-zA-Z0-9-]*',
              error: 'The secret contains invalid characters.'),
          Ask.lengthRange(36, 36),
        ]));
  }
}
