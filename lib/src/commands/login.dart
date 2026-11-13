/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */
import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:dcli_core/dcli_core.dart';
import 'package:dcli_terminal/dcli_terminal.dart';
import 'package:url_builder/url_builder.dart';

import '../api/api.dart';
import '../api/login_request.dart';
import '../exceptions.dart';
import '../onepub_settings.dart';
import '../util/bread_butter_auth.dart';
import '../util/login_persistence.dart';
import '../util/printerr.dart';
import '../util/send_command.dart';
import 'login/trusted.dart';

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
  OnePubLoginCommand() {
    argParser.addFlag('choose',
        negatable: false,
        help:
            'Choose a sign-in method instead of using the remembered method.');
    addSubcommand(_BrowserLoginCommand());
    addSubcommand(_InteractiveLoginCommand());
    addSubcommand(_SsoLoginCommand());
    addSubcommand(TrustedLoginCommand());
  }

  @override
  String get description => blue('Log in to OnePub.');

  @override
  String get name => 'login';

  @override
  Future<int> run() => login(
      routing:
          argResults?['choose'] == true ? const LoginRequest.choose() : null);

  Future<int> login({LoginRequest? routing}) async {
    // checkDartVersion();
    try {
      final persistence = LoginPersistence(OnePubSettings.use());
      await persistence.withLogin(() async {
        await persistence.recover();
        if (routing == null) {
          final remembered =
              await persistence.preferences.load(persistence.server);
          routing = remembered == null
              ? const LoginRequest.choose()
              : LoginRequest.remembered(remembered);
        }
        await API().checkVersion();

        final bb = BreadButter();
        final auth = await bb.auth(routing: routing);

        await persistence.save(auth);

        showWelcome(
            firstLogin: auth.firstLogin,
            organisationName: auth.organisationName,
            operator: auth.operatorEmail);
      });
    } on FetchException catch (e) {
      printerr(red('Unable to connect to '
          '${OnePubSettings.use().onepubApiUrlAsString}. '
          'Error: $e '
          'Check your internet connection.'));
    }
    return 0;
  }

  void showError(EndpointResponse endPointResponse) {
    final error = endPointResponse.errorMessage;

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

// CommandRunner requires a subcommand when a command has children. MyRunner
// routes bare login here so its default does not become an ordinary override.
class _InteractiveLoginCommand extends Command<int> {
  @override
  String get name => '_interactive';

  @override
  String get description => 'Use the selected or remembered sign-in method.';

  @override
  bool get hidden => true;

  @override
  Future<int> run() => (parent! as OnePubLoginCommand).run();
}

class _BrowserLoginCommand extends Command<int> {
  @override
  String get description => 'Log in interactively using a web browser.';

  @override
  String get name => 'browser';

  @override
  Future<int> run() =>
      OnePubLoginCommand().login(routing: const LoginRequest.ordinary());
}

class _SsoLoginCommand extends Command<int> {
  @override
  String get description => 'Log in using your organisation’s enterprise SSO.';

  @override
  String get name => 'sso';

  @override
  String get invocation => '${super.invocation} <organisation-code>';

  @override
  Future<int> run() {
    final arguments = argResults!.rest;
    if (arguments.length != 1) {
      usageException('Provide your organisation SSO code.');
    }
    return OnePubLoginCommand()
        .login(routing: LoginRequest.sso(arguments.single));
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
${blue(urlJoin(OnePubSettings.use().onepubWebUrl, 'Blog?id=zuhnoflygz'))}

The OnePub manual can be found at:
${blue('https://docs.onepub.dev')}

''';
  }

  print('''

${green('Successfully logged into $organisationName as $operator.')}

$firstMessage
''');
}
