import 'dart:convert';
import 'dart:io';

import 'package:dcli/dcli.dart';
import 'package:http/http.dart' as http;

import '../exceptions.dart';
import '../onepub_settings.dart';
import 'log.dart';

Future<void> getCommand({
  required String endpoint,
  bool authorised = true,
  Map<String, String> headers = const {},
}) async {
  try {
    final resolvedEndpoint = '${OnepubSettings().onepubApiUrl}$endpoint';

    final _headers = <String, String>{}..addAll(headers);

    if (authorised) {
      if (!isLoggedIn) {
        throw ExitException(exitCode: 1, message: '''
You must be logged in to run this command.
run: 
  onepub login
  ''');
      }
      final onepubToken = OnepubSettings().onepubToken;

      _headers.addAll({'authorization': onepubToken});
    }

    final url = Uri.parse(resolvedEndpoint);
    final response = await http.get(url, headers: _headers);
    final decodedResponse = bodyAsJsonMap(response.body);

    if (response.statusCode < 400) {
      final status = (decodedResponse['success']
          as Map<String, dynamic>)['message'] as String;
      print('Status: ${green('${response.statusCode}')} '
          '${green(status)}');
    } else {
      final status = (decodedResponse['error']
          as Map<String, dynamic>)['message'] as String;
      print('Status: ${green('${response.statusCode}')} '
          '${green(status)}');
    }
  } on IOException catch (e) {
    printerr(red(e.toString()));
  } finally {}
}

class PostResponse {
  PostResponse(this.status, this.body);
  int status;
  String body;

  Map<String, Object?> asJsonMap() => bodyAsJsonMap(body);
}

Future<PostResponse> postCommand({
  required String endpoint,
  required String body,
  bool authorised = true,
  Map<String, String> headers = const {},
}) async {
  try {
    final resolvedEndpoint = '${OnepubSettings().onepubApiUrl}$endpoint';

    final _headers = <String, String>{}..addAll(headers);

    if (authorised) {
      if (!isLoggedIn) {
        throw ExitException(exitCode: 1, message: '''
You must be logged in to run this command.
run: 
  onepub login
  ''');
      }
      final onepubToken = OnepubSettings().onepubToken;

      _headers.addAll({'authorization': onepubToken});
    }

    final url = Uri.parse(resolvedEndpoint);
    final response = await http.post(url, headers: _headers, body: body);

    return PostResponse(response.statusCode, response.body);
  } on IOException catch (e) {
    logerr(red(e.toString()));
    throw ExitException(exitCode: 1, message: e.toString());
  } finally {}
}

/// Takes the body, assumes its a json string and
/// converts it to a map.
Map<String, dynamic> bodyAsJsonMap(String body) =>
    jsonDecode(body) as Map<String, dynamic>;
