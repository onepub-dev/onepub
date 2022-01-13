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

    await doAuth();
    final credentials = read(Credentials.pathToCredentials).toParagraph();

    final response = await postCommand(
        endpoint: '/api/login', authorised: false, body: credentials);

    if (response.status == 200) {
      final map = response.asJsonMap();
      final authToken = map['authToken'] as String?;
      if (authToken == null) {
        throw ExitException(
            exitCode: 1, message: 'Invalid response. authToken missing');
      }
      OnepubSettings().onepubToken = authToken;
    }
  }
}
