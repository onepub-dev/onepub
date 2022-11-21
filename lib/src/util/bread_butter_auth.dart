/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

/// Some parts of this file come from the unpub_auth project and are subject
/// to MIT license.
import 'dart:async';
import 'dart:io';

import 'package:dcli/dcli.dart';
import 'package:usage/uuid/uuid.dart';

import '../api/api.dart';
import '../api/auth_response.dart';
import '../onepub_settings.dart';
import 'send_command.dart';

class BreadButter {
  late final HttpServer server;
  late final Completer<EndpointResponse?> completer;

  /// Return the auth token or null if the auth failed.
  Future<AuthResponse> auth() async {
    final settings = OnePubSettings.use();

    final authToken = Uuid().generateV4();

    final authUrl = settings.resolveWebEndPoint('clilogin/$authToken');

    final encodedUrl = Uri.encodeFull(authUrl);

    /// Display the browser link to the user
    print('''
To login to OnePub...

From a web browser, go to: 
${blue(encodedUrl)}

Waiting for your authorisation...''');

    /// wait for the user to complete the browser login
    return _waitForResponse(authToken);
  }

  /// Long poll the server and wait for the user to complete
  /// the login.
  /// The server will respond with the onepub token.
  Future<AuthResponse> _waitForResponse(String authToken) async {
    var retry = true;

    late AuthResponse auth;

    final api = API();

    while (retry) {
      auth = await api.awaitLogin(authToken);

      retry = auth.status == AwaitLoginStatus.retry;
      if (retry) {
        sleep(auth.pollInterval);
      }
    }

    return auth;
  }
}
