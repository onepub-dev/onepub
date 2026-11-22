/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */
import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:dcli_terminal/dcli_terminal.dart';

import '../api/api.dart';
import '../device/device_session.dart';
import 'dart:convert';
import '../exceptions.dart';
import '../onepub_settings.dart';
import '../util/login_persistence.dart';
import '../util/one_pub_token_store.dart';

/// onepub Logout `<email>`
///     - if the user doesn't exists sends them an Logout.
class OnePubLogoutCommand extends Command<int> {
  ///
  OnePubLogoutCommand() {
    argParser.addFlag('forget',
        negatable: false,
        help: 'Also forget the sign-in method remembered for this server.');
  }

  @override
  String get description => blue('Log out of OnePub CLI.');

  @override
  String get name => 'logout';

  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      throw ExitException(exitCode: 1, message: red('''
The logout command takes no arguments. Found ${argResults!.rest.join(',')}.
'''));
    }

    final settings = OnePubSettings.use();
    final persistence = LoginPersistence(settings);
    await persistence.recover();
    final onepubApiUrl = settings.onepubApiUrl;
    if (await OnePubTokenStore().isLoggedIn(onepubApiUrl)) {
      final device = await DeviceSession.load(settings, onepubApiUrl);
      await API().checkVersion();
      final response = await API().logout();
      if (response.success) {
        await OnePubTokenStore().clearOldTokens(onepubApiUrl);
        final devices = await DeviceSession.readRegistry(settings);
        devices.remove(onepubApiUrl.toString());
        await DeviceSession.registry(settings)
            .writeAsString(jsonEncode(devices), flush: true);
      }

      if (!response.success) {
        throw ExitException(exitCode: 1, message: response.errorMessage);
      }

      print(green('You have been logged out of the OnePub CLI for '
          '${settings.organisationName} '
          '${device == null ? 'on all your devices' : 'on this device'}.'));
    } else {
      await OnePubTokenStore().clearOldTokens(settings.onepubApiUrl);
      print(orange('You are already logged out.'));
    }

    if (argResults!['forget'] == true) {
      await persistence.preferences.forget(persistence.server);
    }
    return 0;
  }
}
