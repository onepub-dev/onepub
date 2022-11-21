/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */
import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';

import '../api/api.dart';
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
  String get description => blue('Log in to OnePub.');

  @override
  String get name => 'login';

  @override
  Future<int> run() async {
    // checkDartVersion();
    try {
      await API().checkVersion();

      final bb = BreadButter();
      final auth = await bb.auth();

      final settings = OnePubSettings.use()
        ..obfuscatedOrganisationId = auth.obfuscatedOrganisationId
        ..organisationName = auth.organisationName
        ..operatorEmail = auth.operatorEmail
        ..save();

      final onepubApiUrl = settings.onepubApiUrlAsString;

      OnePubTokenStore().addToken(
        onepubApiUrl: onepubApiUrl,
        onepubToken: auth.onepubToken,
      );

      showWelcome(
          firstLogin: auth.firstLogin,
          organisationName: auth.organisationName,
          operator: auth.operatorEmail);
    } on FetchException catch (e, _) {
      printerr(red('Unable to connect to '
          '${OnePubSettings.use().onepubApiUrlAsString}. '
          'Error: $e'
          'Check your internet connection.'));
    }
    return 0;
  }

  void showError(EndpointResponse endPointResponse) {
    final error = endPointResponse.data['message']! as String;

    print(red(error));
  }

  bool inSSH() =>
      Env().exists('SSH_CLIENT') ||
      Env().exists('SSH_CONNECTION') ||
      Env().exists('SSH_TTY');

  // void checkDartVersion() {
  //   var ver = VersionConstraint.parse(Platform.version) as Version;

  //   if (ver.compareTo(VersionConstraint.parse('2.15.0') as Version) < 0) {
  //     throw ExitException(1, '')
  //   }
  // }
  // removed as I think this is set if a user
  //runs ssa-agent to start the ssh-agent on their local machine.
  // Env().exists('SSH_AGENT_PID');
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
${orange('${OnePubSettings.use().onepubWebUrl}/getting-started')}

''';
  }

  print('''

${blue('Successfully logged into $organisationName as $operator.')}

$firstMessage
''');
}
