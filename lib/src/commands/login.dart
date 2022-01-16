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

    final credentials = await doAuth();
    final oauth2AccessToken = credentials.accessToken;

    print('Successfully authorised.\n');

    final response = await sendCommand(
        endpoint: '/api/login',
        authorised: false,
        headers: {'authorization': oauth2AccessToken},
        body: credentials.toJson(),
        method: Method.post);

    if (response.status != 200) {
      throw ExitException(exitCode: 1, message: '''
Login to onepub.dev failed: 
${response.data['message']}''');
    }

    final map = response.data;
    final onepubToken = map['authToken'] as String?;
    if (onepubToken == null) {
      throw ExitException(
          exitCode: 1, message: 'Invalid response. authToken missing');
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
        print('dart pub configured.');
      }
    }, environment: {Credentials.onepubSecretEnvKey: onepubToken});
  }
}
