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
  String get description => 'Log in to onepub.dev.';

  @override
  String get name => 'login';

  @override
  Future<void> run() async {
    loadSettings();

    try {
      final endPointResponse = await bbAuth();
      if (endPointResponse == null) {
        throw ExitException(
            exitCode: 1, message: 'Invalid response. onePubToken not returned');
      }

      if (endPointResponse.success) {
        final onepubToken = endPointResponse.data['onePubToken'] as String?;
        final firstLogin = endPointResponse.data['firstLogin'] as bool?;
        if (onepubToken == null || firstLogin == null) {
          throw ExitException(
              exitCode: 1,
              message: 'Invalid response. authToken or firstLogin missing');
        }
        OnePubTokenStore().save(onepubToken);

        showWelcome(firstLogin: firstLogin);
      } else {
        showError(endPointResponse);
      }
    } on FetchException {
      printerr(red('Unable to connect to the onepub.dev server. '
          'Check your internet connection.'));
    }
  }

  void showError(EndpointResponse endPointResponse) {
    final error = endPointResponse.data['message']! as String;

    print(red(error));
  }
}

void showWelcome({required bool firstLogin}) {
  var firstMessage = '';
  if (firstLogin) {
    firstMessage = '''
Welcome to OnePub.
Read the getting started guide at:
${orange('https://onepub.dev/getting-started')}

''';
  }

  print('''

${blue('Successfully logged in.')}

$firstMessage
''');
}
