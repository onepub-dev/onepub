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

import '../exceptions.dart';
import '../onepub_settings.dart';
import 'send_command.dart';

class BreadButter {
  late final HttpServer server;
  late final Completer<EndpointResponse?> completer;

  /// Return the auth token or null if the auth failed.
  Future<AuthResponse> auth() async {
    final settings = OnePubSettings.use;

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

    while (retry) {
      final response = await sendCommand(
          command: 'member/awaitLogin/$authToken',
          commandType: CommandType.cli,
          authorised: false);

      auth = decantResponse(response);
      retry = auth.status == Status.retry;
      if (retry) {
        sleep(auth.pollInterval);
      }
    }

    return auth;
  }

  AuthResponse decantResponse(EndpointResponse? response) {
    if (response == null) {
      throw ExitException(
          exitCode: 1, message: 'Invalid response. onePubToken not returned');
    }

    return AuthResponse.parse(response);
  }
}

class AuthResponse {
  AuthResponse._internal();

  factory AuthResponse.parse(EndpointResponse response) {
    final auth = AuthResponse._internal();
    if (response.success == true) {
      auth.status = parseStatus(
          response.data['status'] as String? ?? Status.authFailed.toString());

      switch (auth.status) {
        case Status.authSucceeded:
          auth
            ..onepubToken = response.data['onePubToken']! as String
            ..firstLogin = response.data['firstLogin']! as bool
            ..operatorEmail = response.data['operatorEmail']! as String
            ..organisationName = response.data['organisationName']! as String
            ..obfuscatedOrganisationId =
                response.data['obfuscatedOrganisationId']! as String;
          break;
        case Status.retry:
          auth.pollInterval = response.data['pollInterval'] as int? ?? 3;
          break;
        case Status.authFailed:
          throw ExitException(exitCode: 1, message: 'Authentication failed');
        case Status.timeout:
          throw ExitException(exitCode: 1, message: 'Login Timed out');
      }
      return auth;
    } else {
      throw ExitException(
          exitCode: 1, message: 'Login failed: ${response.data['error']}');
    }
  }

  late final Status status;
  late final int pollInterval;

  late final String onepubToken;
  late final bool firstLogin;
  late final String operatorEmail;
  late final String organisationName;
  late final String obfuscatedOrganisationId;
}

enum Status {
  authSucceeded,
  authFailed,

  /// the auth hasn't yet been completed.
  /// wait for pollInterval seconds and retry.
  retry,

  /// The auth has been cancelled as the user
  /// didn't respond in a timely manner (usually five minutes)
  timeout
}

Status parseStatus(String name) =>
    Status.values.firstWhere((e) => e.toString() == 'Status.$name');
