import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';

import '../exceptions.dart';
import '../onepub_settings.dart';
import '../util/one_pub_token_store.dart';
import '../util/send_command.dart';
import 'bbauth.dart';

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
class LoginCommand extends Command<void> {
  ///
  LoginCommand();

  @override
  String get description => 'Log in to ${OnePubSettings.onepubHostName}.';

  @override
  String get name => 'login';

  @override
  Future<void> run() async {
    loadSettings();

    try {
      final tempAuthTokenResponse = await bbAuth();
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
              message: 'Invalid response. missing authrization data');
        }

        print(onepubToken);

        OnePubTokenStore().save(
            onepubToken: onepubToken,
            obfuscatedOrganisationId: obfuscatedOrganisationId);
        OnePubSettings()
          ..organisationName = organisationName
          ..save();

        showWelcome(
            firstLogin: firstLogin,
            organisationName: organisationName,
            operator: operatorEmail);
      } else {
        showError(tempAuthTokenResponse);
      }
    } on FetchException {
      printerr(red(
          'Unable to connect to the ${OnePubSettings.onepubHostName} server. '
          'Check your internet connection.'));
    }
  }

  void showError(EndpointResponse endPointResponse) {
    final error = endPointResponse.data['message']! as String;

    print(red(error));
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
${orange('https://${OnePubSettings.onepubHostName}/getting-started')}

''';
  }

  print('''

${blue('Successfully logged into $organisationName as $operator.')}

$firstMessage
''');
}
