import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';

import '../onepub_settings.dart';
import '../util/log.dart';
import '../util/send_command.dart';

///
class DoctorCommand extends Command<void> {
  ///
  DoctorCommand();

  @override
  String get description => 'Displays the onepub settings';

  @override
  String get name => 'doctor';

  @override
  void run() {
    if (!exists(OnepubSettings.pathToSettings)) {
      logerr(red('''You must run 'onepub install' first.'''));
      exit(1);
    }
    OnepubSettings.load();

    print(blue('Dart'));
    print('Dart version: ${DartSdk().version}');
    print('Dart path: ${DartSdk().pathToDartExe}');

    print(blue('\nURLs'));
    print('Web site: ${OnepubSettings.onepubWebUrl}');
    print('Repository: ${OnepubSettings().onepubApiUrl}');

    print(blue('\nEnvironment'));
    envStatus(OnepubSettings.pubHostedUrlKey);
    envStatus('PUB_CACHE');

    tokenStatus();

    print('');
    _status();
  }

  void envStatus(String key) {
    if (Env().exists(key)) {
      print('$key=${env[key]}');
    } else {
      print('$key not found.');
    }
  }

  Future<void> _status() async {
    print(blue('\nStatus'));
    if (OnepubSettings().isLoggedIn) {
      print('Logged In: true');
    } else {
      print(orange('''
You are not logged into onepub.
run:
onepub login'''));
    }
    try {
      const endpoint = '/api/status';

      echo('checking status...  ');

      final response = await sendCommand(endpoint: endpoint);

      if (response.status == 200) {
        print(green(response.data['message']! as String));
      } else {
        print(red(response.data['error']! as String));
      }
    } on IOException catch (e) {
      printerr(red(e.toString()));
    } finally {}
  }
}

void tokenStatus() {
  print(blue('\nRepository tokens'));
  final progress =
      DartSdk().runPub(args: ['token', 'list'], progress: Progress.capture());

  if (progress.exitCode != 0) {
    printerr(red(progress.toParagraph()));
  } else {
    final tokenLines = progress.toList().skip(1);
    if (tokenLines.isEmpty) {
      print(red('Onepub has not been added to the pub token list.'));
      print('''
run:
onepub login''');
    } else {
      var found = false;
      for (final line in tokenLines) {
        if (line == OnepubSettings().onepubApiUrl) {
          print(green(line));
          found = true;
        } else {
          print(line);
        }
      }
      if (!found) {
        print(red('\nOnepub has not been added to the pub token list.'));
        print('''
run: onepub login''');
      }
    }
  }
}
