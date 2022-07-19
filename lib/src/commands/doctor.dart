/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';

import '../api/api.dart';
import '../onepub_settings.dart';
import '../util/one_pub_token_store.dart';

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
    withSettings(() {
      print(blue('Dart'));
      print('Dart version: ${DartSdk().version}');
      print('Dart path: ${DartSdk().pathToDartExe}');

      print(blue('\nURLs'));
      print('Web site: ${OnePubSettings.use.onepubWebUrl}');
      print('API endpoint: ${OnePubSettings.use.onepubApiUrl}');

      print(blue('\nEnvironment'));
      envStatus('PUB_CACHE');
      envStatus('PATH');

      tokenStatus();

      print('');
      _status();
    });
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
      print('Member: ${OnePubSettings.use.operatorEmail}');
      print('Organisation: ${OnePubSettings.use.organisationName}');
    } else {
      print(orange('''
You are not logged into OnePub.
run: onepub login'''));
    }
    try {
      echo('checking status...  ');

      final status = await API().status();

      if (status.statusCode == 200) {
        print('');
        print(green(status.message));
      } else {
        print('');
        print(red(status.message));
      }
    } on IOException catch (e) {
      printerr(red(e.toString()));
    } finally {}
    print('');
  }
}

void tokenStatus() {
  print(blue('\nRepository tokens'));

  final store = OnePubTokenStore();
  if (!store.isLoggedIn) {
    print(red('No tokens found.'));
    return;
  }

  for (final credential in store.credentials) {
    print(credential.url);
  }
}
