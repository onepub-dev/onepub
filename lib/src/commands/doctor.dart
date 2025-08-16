/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dcli_core/dcli_core.dart';
import 'package:dcli_input/dcli_input.dart';
import 'package:dcli_terminal/dcli_terminal.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:strings/strings.dart';

import '../api/api.dart';
import '../onepub_settings.dart';
import '../util/one_pub_token_store.dart';
import '../util/printerr.dart';
import '../util/pub_cache.dart';
import '../version/version.g.dart';

///
class DoctorCommand extends Command<int> {
  ///
  DoctorCommand();

  @override
  String get description => blue('Displays the onepub settings.');

  @override
  String get name => 'doctor';

  @override
  Future<int> run() async {
    _printPlatform();
    _printURLs();
    _printEnvironment();
    _printShell();

    await tokenStatus();
    await _status();
    return 0;
  }

  void _printURLs() {
    print('');

    print(blue('\nURLs'));
    _colprint(['Web site:', OnePubSettings.use().onepubWebUrl]);
    _colprint(['API endpoint:', OnePubSettings.use().onepubApiUrlAsString]);
  }

  void _printEnvironment() {
    print(blue('\nEnvironment'));
    _colprint(['Pub Cache:', privatePath(PubCache().pathTo)]);
    envStatus('PUB_CACHE');
    _printPATH();
  }

  void envStatus(String key) {
    if (Env().exists(key)) {
      _colprint(['$key:', env[key]]);
    } else {
      _colprint(['$key:', 'not set and not used.']);
    }
  }

  void _printPATH() {
    print('PATH:');
    for (final path in PATH) {
      final line = privatePath(path);
      var error = '';
      if (Strings.isBlank(path)) {
        error = red(' ERROR: path is blank.');
      } else {
        if (!exists(path)) {
          error = red(' ERROR: path does not exist.');
        }
      }

      _colprint(['', line, error]);
    }
  }

  void _printShell() {
    print('');
    print(blue('Shell Settings'));
    _colprint([r'$SHELL:', env['SHELL'] ?? '']);

    //  restore once dcli resolves waitfor issue.
    // final shell = Shell.current;
    // _colprint(['Detected:', shell.name]);
    // if (shell.hasStartScript) {
    //   final startScriptPath = shell.pathToStartScript;
    //   _colprint(['Start script:', privatePath(startScriptPath ?? 'not found')]);
    // } else {
    //   _colprint(['Start script:', 'not supported by shell']);
    // }
  }

  Future<void> _status() async {
    print('');
    print(blue('Status'));
    final settings = OnePubSettings.use();
    if (await OnePubTokenStore().isLoggedIn(settings.onepubApiUrl)) {
      _colprint(['Logged In:', 'true']);
      _colprint(['Active Member:', settings.operatorEmail]);
      _colprint(['Organisation:', settings.organisationName]);
    } else {
      print(orange('''
You are not logged into OnePub.
run: onepub login'''));
    }
    try {
      await echo('checking status...  ');

      final status = await API().status();

      if (status.statusCode == 200) {
        print('');
        print(green(status.message));
        print('');
        print('Server Version: ${status.version}');

        if (Version.parse(packageVersion).major < status.version.major) {
          print(red('${'*' * 40} ERROR ${'*' * 40}'));
          print(red(
              'The OnePub Server version does not match your onepub version.'));
          print('Please upgraded onepub by running:');
          print('dart pub global activate onepub');
          print(red('${'*' * 40} ERROR ${'*' * 40}'));
        }
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

Future<void> tokenStatus() async {
  print(blue('\nRepository tokens'));

  final store = OnePubTokenStore();

  var hasOnePubToken = false;
  for (final credential in await store.credentials) {
    if (credential.url.host == 'onepub.dev' ||
        credential.url.host == 'beta.onepub.dev') {
      hasOnePubToken = true;
    }
  }

  if (!await store.isLoggedIn(OnePubSettings.use().onepubApiUrl)) {
    print(red('Not logged into OnePub.'));
    if (hasOnePubToken) {
      print('''
Whilst you are not logged into OnePub you can still 
perform some operations as you have an active OnePub token(s) 
as listed below.
      ''');
    }
  }

  for (final credential in await store.credentials) {
    print(credential.url);
  }
}

void _printPlatform() {
  print(blue('Platform'));

  _colprint(['Dart version:', Platform.version]);
  _colprint(['Dart path:', Platform.executable]);
  print('');

  _colprint(['OS:', Platform.operatingSystem]);
  _colprint(
    ['OS version:', Platform.operatingSystemVersion],
  );

  print('');
  _colprint(
    ['Locale:', Platform.localeName],
  );
  _colprint(['Path separator:', Platform.pathSeparator]);
}

void _colprint(List<String?> cols) {
  //cols[0] = green(cols[0]);
  print(Format().row(cols, widths: [15, 35, -1], delimiter: ' '));
}
