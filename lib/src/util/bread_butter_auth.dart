/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

/// Some parts of this file come from the unpub_auth project and are subject
/// to MIT license.
import 'dart:async';
import 'dart:io';

import 'package:dcli/dcli.dart';
import 'package:http_multi_server/http_multi_server.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../onepub_settings.dart';
import 'send_command.dart';

class BreadButter {
  final int _port = 42666;
  late final HttpServer server;
  late final Completer<EndpointResponse?> completer;

  /// Return the auth token or null if the auth failed.
  Future<EndpointResponse?> auth() async {
    final onepubUrl = OnePubSettings.load().onepubWebUrl;
    final authUrl = OnePubSettings().resolveWebEndPoint('clilogin');

    final encodedUrl = Uri.encodeFull(authUrl);

    print('''
To login to OnePub.

From a web browser, go to 
${blue(encodedUrl)}

Waiting for your authorisation...''');

    return _waitForResponse(onepubUrl);
  }

  /// Returns a map with the response
  Future<EndpointResponse?> _waitForResponse(
    String onepubWebUrl,

    // oauth2.AuthorizationCodeGrant grant
  ) async {
    completer = Completer<EndpointResponse?>();
    server = await bindServer(_port);

    final onepuburl = OnePubSettings().onepubUrl;
    final headers = {'Access-Control-Allow-Origin': onepuburl!};
    shelf.Response _cors(shelf.Response response) =>
        response.change(headers: headers);

    final _fixCORS = shelf.createMiddleware(responseHandler: _cors);

// Pipeline handlers
    final handler = const shelf.Pipeline()
        .addMiddleware(_fixCORS)
        //.addMiddleware(shelf.logRequests())
        .addHandler(_oauthHandler);

    shelf_io.serveRequests(server, handler);

    return completer.future;
  }

  FutureOr<shelf.Response> _oauthHandler(shelf.Request request) async {
    await server.close();

    try {
      if (request.url.queryParameters.keys.contains('app_id') &&
          request.url.queryParameters.keys.contains('authentication_token')) {
        print('Authorisation received, processing...');

        final appId = request.url.queryParameters['app_id']!;
        final token = request.url.queryParameters['authentication_token']!;

        // Forward the oauth details to the server so it can validate us.
        final response = await sendCommand(
            command: '/member/oauth'
                '?app_id=$appId&authentication_token=$token',
            authorised: false);

        if (!response.success) {
          completer.complete(response);
          return shelf.Response.internalServerError(
              body: 'OnePub CLI failed to authenticate.');
        }

        /// Redirect to authorised page.
        completer.complete(response);
        return shelf.Response.ok('OnePub CLI successfully authorised.');
      } else {
        completer.complete(null);

        /// Forbid all other requests.
        return shelf.Response.notFound('Invalid Request');
      }
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      completer.complete(null);

      return shelf.Response.internalServerError(body: e.toString());
    }
  }

  /// Bind local server to handle oauth redirect
  Future<HttpServer> bindServer(int port) async {
    final server = await HttpMultiServer.loopback(port);
    server.autoCompress = true;
    return server;
  }

  Map<String, String> queryToMap(String queryList) {
    final map = <String, String>{};
    for (final pair in queryList.split('&')) {
      final split = _split(pair, '=');
      if (split.isEmpty) {
        continue;
      }
      final key = _urlDecode(split[0]);
      final value = split.length > 1 ? _urlDecode(split[1]) : '';
      map[key] = value;
    }
    return map;
  }

  List<String> _split(String toSplit, String pattern) {
    if (toSplit.isEmpty) {
      return <String>[];
    }

    final index = toSplit.indexOf(pattern);
    if (index == -1) {
      return [toSplit];
    }
    return [
      toSplit.substring(0, index),
      toSplit.substring(index + pattern.length)
    ];
  }

  String _urlDecode(String encoded) =>
      Uri.decodeComponent(encoded.replaceAll('+', ' '));
}
