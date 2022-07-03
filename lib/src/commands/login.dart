/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';

import '../exceptions.dart';
import '../onepub_settings.dart';
import '../util/bread_butter_auth.dart';
import '../util/one_pub_token_store.dart';
import '../util/send_command.dart';

/// onepub login
/// We trigger oauth by showing url
// We then do a long poll to the server and wait for oauth to complete
// The long poll adds a pending request to a guava cache (with expiry)

// The oath completes on the server
// The server checks if there is an existing onepub token for the member
// If so we return the token as this allows mulitple devices to be authed.
// If not we create a new onepub token
// We return the onpub token to the cli and it stores it.
// The cli then passed the onepub token each time it needs to interact.
// No oauth is required we just check the onepub token is invalid.
// A logout on any device will invalidate the token.
// A manager can invalidate the token from the web site.
class OnePubLoginCommand extends Command<int> {
  ///
  OnePubLoginCommand();

  @override
  String get description => 'Log in to OnePub.';

  @override
  String get name => 'login';

  @override
  Future<int> run() async {
    loadSettings();

    if (inSSH()) {
      throw ExitException(exitCode: -1, message: """
${red('onepub login will not work from an ssh shell.')}

Instead:
Exit your ssh session and run:
${green('onepub export')}

Restart your ssh session and run:
${green('onepub import --ask')}
""");
    }

    try {
      final tempAuthTokenResponse = await breadButterAuth();
      if (tempAuthTokenResponse == null) {
        throw ExitException(
            exitCode: 1, message: 'Invalid response. onePubToken not returned');
      }

      if (tempAuthTokenResponse.success) {
        final onepubToken =
            tempAuthTokenResponse.data['onePubToken'] as String?;
        final firstLogin = tempAuthTokenResponse.data['firstLogin'] as bool?;
        final operatorEmail =
            tempAuthTokenResponse.data['operatorEmail'] as String?;
        final organisationName =
            tempAuthTokenResponse.data['organisationName'] as String?;
        final obfuscatedOrganisationId =
            tempAuthTokenResponse.data['obfuscatedOrganisationId'] as String?;
        if (onepubToken == null ||
            firstLogin == null ||
            organisationName == null ||
            operatorEmail == null ||
            obfuscatedOrganisationId == null) {
          print(tempAuthTokenResponse.data);
          throw ExitException(
              exitCode: 1,
              message: 'Invalid response. missing authorization data');
        }

        OnePubTokenStore().save(
            onepubToken: onepubToken,
            organisationName: organisationName,
            obfuscatedOrganisationId: obfuscatedOrganisationId,
            operatorEmail: operatorEmail);

        showWelcome(
            firstLogin: firstLogin,
            organisationName: organisationName,
            operator: operatorEmail);
      } else {
        showError(tempAuthTokenResponse);
      }
    } on FetchException {
      printerr(red('Unable to connect to ${OnePubSettings().onepubApiUrl} . '
          'Check your internet connection.'));
    }
    return 0;
  }

  void showError(EndpointResponse endPointResponse) {
    final error = endPointResponse.data['message']! as String;

    print(red(error));
  }

  bool inSSH() {
    return Env().exists('SSH_CLIENT') ||
        Env().exists('SSH_CONNECTION') ||
        Env().exists('SSH_TTY');
  }
}

void showWelcome(
    {required bool firstLogin,
    required String organisationName,
    required String operator}) {
  var firstMessage = '';
  if (firstLogin) {
    firstMessage = '''
Welcome to OnePub.
Read the getting started guide at:
${orange('${OnePubSettings().onepubWebUrl}/getting-started')}

''';
  }

  print('''

${blue('Successfully logged into $organisationName as $operator.')}

$firstMessage
''');
}
