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
      _printPlatform();
      _printURLs();
      _printEnvironment();
      _printShell();

      tokenStatus();
      _status();
    });
    return 0;
  }

  void _printURLs() {
    print('');

    print(blue('\nURLs'));
    print('Web site: ${OnePubSettings.use.onepubWebUrl}');
    print('API endpoint: ${OnePubSettings.use.onepubApiUrl}');
  }

  void _printEnvironment() {
    print(blue('\nEnvironment'));
    envStatus('PUB_CACHE');
    _printPATH();
  }

  void envStatus(String key) {
    if (Env().exists(key)) {
      print('$key: ${env[key]}');
    } else {
      print('$key: not set and not used.');
    }
  }

  void _printPATH() {
    print('PATH');
    for (final path in PATH) {
      final line = privatePath(path);
      var error = '';
      if (!exists(path)) {
        error = red(' ERROR: path does not exist.');
      }
      _colprint(['', line, error]);
    }
  }

  void _printShell() {
    print('');
    print(blue('Shell Settings'));
    _colprint([r'$SHELL', env['SHELL'] ?? '']);

    final shell = Shell.current;
    _colprint(['detected', shell.name]);

    if (shell.hasStartScript) {
      final startScriptPath = shell.pathToStartScript;
      _colprint(['Start script', privatePath(startScriptPath ?? 'not found')]);
    } else {
      _colprint(['Start sript', 'not supported by shell']);
    }
  }

  Future<void> _status() async {
    print('');
    print(blue('Status'));
    if (OnePubTokenStore().isLoggedIn) {
      print('Logged In: true');
      print('Active Member: ${OnePubSettings.use.operatorEmail}');
      print('Active Organisation: ${OnePubSettings.use.organisationName}');
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

void _printPlatform() {
  print(blue('Platform'));

  _colprint(['OS', Platform.operatingSystem]);
  print(
    Format().row(
      ['OS version', Platform.operatingSystemVersion],
      widths: [17, -1],
    ),
  );
  _colprint(['Path separator', Platform.pathSeparator]);
  print('');

  print('Dart version: ${DartSdk().version}');
  print('Dart path: ${DartSdk().pathToDartExe}');
}

void _colprint(List<String?> cols) {
  //cols[0] = green(cols[0]);
  print(Format().row(cols, widths: [15, 35, -1], delimiter: ' '));
}
