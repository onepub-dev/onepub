/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'dart:async';
import 'dart:io';

import 'package:dcli_terminal/dcli_terminal.dart';
import 'package:uuid/uuid.dart';

import '../api/api.dart';
import '../api/auth_response.dart';
import '../exceptions.dart';
import '../onepub_settings.dart';
import 'send_command.dart';

class BreadButter {
  late final HttpServer server;
  late final Completer<EndpointResponse?> completer;

  /// Return the auth token or null if the auth failed.
  Future<AuthResponse> auth() {
    final settings = OnePubSettings.use();
    final authToken = const Uuid().v4();
    final authUrl = settings.resolveWebEndPoint('clilogin/$authToken');
    final encodedUrl = Uri.encodeFull(authUrl);
    final api = API();

    return waitForLoginResponse(
      () => api.awaitLogin(authToken),
      onReady: () => print('''
To login to OnePub...

From a web browser, go to: 
${blue(encodedUrl)}

Waiting for your authorisation...'''),
    );
  }
}

/// Waits for browser login while honoring the server's retry interval.
Future<AuthResponse> waitForLoginResponse(
  Future<AuthResponse> Function() poll, {
  void Function()? onReady,
  Future<void> Function(Duration) delay = Future<void>.delayed,
  DateTime Function() now = DateTime.now,
  Duration timeout = const Duration(minutes: 2),
}) async {
  final deadline = now().add(timeout);
  var reportedLimit = false;
  var consecutiveLimits = 0;
  var ready = false;
  while (now().isBefore(deadline)) {
    final auth = await poll();
    if (auth.status != AwaitLoginStatus.rateLimited && !ready) {
      onReady?.call();
      ready = true;
    }
    if (auth.status != AwaitLoginStatus.retry &&
        auth.status != AwaitLoginStatus.rateLimited) {
      return auth;
    }
    if (auth.status == AwaitLoginStatus.rateLimited && !reportedLimit) {
      print('Too many login requests from this network; waiting to retry.');
      reportedLimit = true;
    }
    if (auth.status == AwaitLoginStatus.rateLimited) {
      consecutiveLimits++;
    } else {
      consecutiveLimits = 0;
    }
    final remaining = deadline.difference(now());
    if (remaining <= Duration.zero) {
      break;
    }
    final backoff = switch (consecutiveLimits) {
      1 => 3,
      2 => 6,
      3 => 12,
      4 => 24,
      > 4 => 30,
      _ => 0,
    };
    final interval = Duration(
      seconds: auth.pollInterval > backoff ? auth.pollInterval : backoff,
    );
    await delay(interval < remaining ? interval : remaining);
  }
  throw ExitException(exitCode: 1, message: 'Login Timed out');
}
