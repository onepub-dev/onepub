import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';
import 'package:http/http.dart' as http;

import '../onepub_settings.dart';
import '../util/log.dart';

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

    print('Web app via: '
        '${blue(OnepubSettings.onepubWebUrl)}');

    if (Env().exists(OnepubSettings.pubHostedUrlKey)) {
      print('${OnepubSettings.pubHostedUrlKey}='
          '${env[OnepubSettings.pubHostedUrlKey]}');
    } else {
      print('');
      print(orange(
          'Environment variable ${OnepubSettings.pubHostedUrlKey} not found!'));
    }

    print('');
    _status();
  }

  Future<void> _status() async {
    StreamSubscription<String>? client;
    try {
      // client = await HttpClient()
      //     .getUrl(Uri.parse(
      //         '${OnepubSettings().onepubApiUrl}/api/status')) // produces a request object
      //     .then((request) => request.close()) // sends the request
      //     .then((response) => response
      //         .transform(const Utf8Decoder())
      //         .listen(print)); // transforms and prints the response

      final endpoint = '${OnepubSettings().onepubApiUrl}/api/status';

      final url = Uri.parse(endpoint);
      final response = await http.get(url);
      final decodedResponse = jsonDecode(response.body) as Map;
      final status = (decodedResponse['success']
          as Map<String, dynamic>)['message'] as String;
      print('Status: ${green('${response.statusCode}')} '
          '${green(status)}');
    } on IOException catch (e) {
      printerr(red(e.toString()));
    } finally {
      if (client != null) {
        await client.cancel();
      }
    }
  }
}
