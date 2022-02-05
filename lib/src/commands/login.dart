import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';

import '../exceptions.dart';
import '../onepub_settings.dart';
import '../token_store/credential.dart';
import '../token_store/hosted.dart';
import '../token_store/io.dart';
import '../token_store/token_store.dart';
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
      final responseData = await bbAuth();
      if (responseData == null) {
        throw ExitException(
            exitCode: 1, message: 'Invalid response. onePubToken not returned');
      }

      print('Successfully authorised.\n');

      final onepubToken = responseData['onePubToken'] as String?;
      final firstLogin = responseData['firstLogin'] as bool?;
      if (onepubToken == null || firstLogin == null) {
        throw ExitException(
            exitCode: 1,
            message: 'Invalid response. authToken or firstLogin missing');
      }
      OnepubSettings()
        ..onepubToken = onepubToken
        ..save();

//       withEnvironment(() {
      final store = TokenStore(dartConfigDir);
      final hostedUrl =
          validateAndNormalizeHostedUrl(OnepubSettings().onepubWebUrl);
      store.addCredential(Credential.token(hostedUrl, onepubToken));
      showWelcome(firstLogin: firstLogin);

      //   final progress = DartSdk().runPub(args: [
      //     'token',
      //     'add',
      //     '--env-var=${Credentials.onepubSecretEnvKey}',
      //     OnepubSettings().onepubWebUrl
      //   ], nothrow: true, progress: Progress.capture());
      //   if (progress.exitCode != 0) {
      //     printerr(red('Failed to add the authorisation token '
      //'to dart pub.'));
      //     printerr(progress.toParagraph());
      //   } else {
      //     showWelcome(firstLogin: firstLogin);
      //   }
      // }, environment: {Credentials.onepubSecretEnvKey: onepubToken});
    } on FetchException {
      printerr(red('Unable to connect to the onepub.dev server. '
          'Check your internet connection.'));
    }
  }
}

void showWelcome({required bool firstLogin}) {
  print('Successfully logged in.');

  if (firstLogin) {
    print('''

Welcome to onepub.dev.
Read the getting started guide at:
${blue('https://onepub.dev/getting-started')}
''');
  }
}
