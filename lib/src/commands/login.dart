import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';

import '../exceptions.dart';
import '../onepub_settings.dart';
import '../util/credentials.dart';
import '../util/send_command.dart';
import 'oauth2.dart';

/// onepub login
class LoginCommand extends Command<void> {
  ///
  LoginCommand();

  @override
  String get description => 'Logins a person into onepub.dev.';

  @override
  String get name => 'login';

  @override
  Future<void> run() async {
    loadSettings();

    final oauth2AccessToken = await doAuth();
    if (oauth2AccessToken == null) {
      throw ExitException(
          exitCode: 1, message: 'Invalid response. onePubToken not returned');
    }

    print('Successfully authorised.\n');

    final response = await sendCommand(
        command: 'login',
        authorised: false,
        headers: {'authorization': oauth2AccessToken},
        method: Method.post);

    if (response.status != 200) {
      throw ExitException(exitCode: 1, message: '''
Login to onepub.dev failed: 
${response.data['message']}''');
    }

    final map = response.data;
    final onepubToken = map['onePubToken'] as String?;
    final firstLogin = map['firstLogin'] as bool?;
    if (onepubToken == null || firstLogin == null) {
      throw ExitException(
          exitCode: 1,
          message: 'Invalid response. authToken or firstLogin missing');
    }
    OnepubSettings()
      ..onepubToken = onepubToken
      ..save();

    print(OnepubSettings().onepubApiUrl);
    withEnvironment(() {
      final progress = DartSdk().runPub(args: [
        'token',
        'add',
        '--env-var=${Credentials.onepubSecretEnvKey}',
        OnepubSettings().onepubApiUrl
      ], nothrow: true, progress: Progress.capture());
      if (progress.exitCode != 0) {
        printerr(red('Failed to add the authorisation token to dart pub.'));
        printerr(progress.toParagraph());
      } else {
        showWelcome(firstLogin: firstLogin);
      }
    }, environment: {Credentials.onepubSecretEnvKey: onepubToken});
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
