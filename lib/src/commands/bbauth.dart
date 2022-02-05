/// Some parts of this file come from the unpub_auth project and are subject
/// to MIT license.
import 'dart:async';

import 'package:dcli/dcli.dart';

import '../onepub_settings.dart';
import '../util/send_command.dart';

/// Return the auth token or null if the auth failed.
Future<Map<String, Object?>?> bbAuth(String tempToken) async {
  final callbackUrl =
      'https://onepub.dev/api/oauthcallback?tempToken=$tempToken';

  final onepubUrl = OnepubSettings.load().onepubWebUrl;
  final authUrl = OnepubSettings()
      .resolveWebEndPoint('clilogin', queryParams: 'callback=$callbackUrl');

  final encodedUrl = Uri.encodeFull(authUrl);

  print('''
To login to Onepub.
From a web browser, go to 

${blue(encodedUrl)}

When prompted Sign in.

Waiting for your authorisation...''');

  return _waitForResponse(onepubUrl, tempToken);
}

/// Returns the token
Future<Map<String, Object?>?> _waitForResponse(
    String onepubWebUrl, String tempToken) async {
  final response =
      await sendCommand(command: 'waitForAuth?tempToken=$tempToken');

  if (!response.success) {
    return null;
  }
  return response.data;
}
