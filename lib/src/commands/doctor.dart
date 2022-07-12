/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';

import '../onepub_settings.dart';
import '../util/log.dart';
import '../util/one_pub_token_store.dart';
import '../util/send_command.dart';

///
class DoctorCommand extends Command<int> {
  ///
  DoctorCommand();

  @override
  String get description => blue('Displays the onepub settings.');

  @override
  String get name => 'doctor';

  @override
  int run() {
    if (!exists(OnePubSettings.pathToSettings)) {
      logerr(red('''Something went wrong, could not find settings file.'''));
      exit(1);
    }
    OnePubSettings.load();

    print(blue('Dart'));
    print('Dart version: ${DartSdk().version}');
    print('Dart path: ${DartSdk().pathToDartExe}');

    print(blue('\nURLs'));
    print('Web site: ${OnePubSettings().onepubWebUrl}');
    print('API endpoint: ${OnePubSettings().onepubApiUrl}');

    print(blue('\nEnvironment'));
    envStatus('PUB_CACHE');
    envStatus('PATH');

    tokenStatus();

    print('');
    _status();
    return 0;
  }

  void envStatus(String key) {
    if (Env().exists(key)) {
      print('$key: ${env[key]}');
    } else {
      print('$key: not set.');
    }
  }

  Future<void> _status() async {
    print(blue('Status'));
    if (OnePubTokenStore().isLoggedIn) {
      print('Logged In: true');
      print('Member: ${OnePubSettings().operatorEmail}');
      print('Organisation: ${OnePubSettings().organisationName}');
    } else {
      print(orange('''
You are not logged into OnePub.
run: onepub login'''));
    }
    try {
      const endpoint = '/status';
      echo('checking status...  ');

      final response = await sendCommand(command: endpoint, authorised: false);

      if (response.status == 200) {
        print('');
        print(green(response.data['message']! as String));
      } else {
        print('');
        print(red(response.data['message']! as String));
      }
    } on IOException catch (e) {
      printerr(red(e.toString()));
    } finally {}
    print('');
  }
}

void tokenStatus() {
  print(blue('\nRepository tokens'));

  var store = OnePubTokenStore();
  if (!store.isLoggedIn) {
    print(red('No tokens found.'));
    return;
  }

  for (final credential in store.credentials) {
    print(credential.url);
  }
}
