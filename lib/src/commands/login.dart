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

    final response = await postCommand(
        endpoint: '/api/login',
        authorised: false,
        headers: {'authorization': oauth2AccessToken},
        body: credentials.toJson());

    if (response.status != 200) {
      throw ExitException(
          exitCode: 1,
          message: 'Login to onpub.dev failed: '
              '${(response.asJsonMap()['error']! as Map)['message']!}');
    }

    final map = response.asJsonMap();
    final onepubToken = (map['success']! as Map)['authToken'] as String?;
    if (onepubToken == null) {
      throw ExitException(
          exitCode: 1, message: 'Invalid response. authToken missing');
    }
    OnepubSettings()
      ..onepubToken = onepubToken
      ..save();

    withEnvironment(() {
      DartSdk().runPub(args: [
        'token',
        'add',
        '--env-var=${Credentials.onpubSecretEnvKey}',
        OnepubSettings.onepubWebUrl
      ]);
    }, environment: {Credentials.onpubSecretEnvKey: onepubToken});
  }
}
