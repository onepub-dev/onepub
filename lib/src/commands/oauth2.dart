/// Some parts of this file come from the unpub_auth project and are subject
/// to MIT license.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dcli/dcli.dart';
import 'package:http/http.dart' as http;
import 'package:http_multi_server/http_multi_server.dart';
import 'package:oauth2/oauth2.dart' as oauth2;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../util/credentials.dart';

const _tokenEndpoint = 'https://oauth2.googleapis.com/token';
const _authEndpoint = 'https://accounts.google.com/o/oauth2/auth';
const _scopes = ['openid', 'https://www.googleapis.com/auth/userinfo.email'];

/// gconsole oauth2 client id for onepub.dev
String get _identifier => utf8.decode(base64.decode(
// ignore: lines_longer_than_80_chars
    '135837931136-kellgulhcooog2fcff38u448gib2ctkd.apps.googleusercontent.com'));

/// gconsole oauth2 client secret for onepub.dev
String get _secret =>
    utf8.decode(base64.decode('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'));

Future<void> doAuth() async {
  final client = await _clientWithAuthorization();
  writeNewCredentials(client.credentials);
  print(client.credentials.accessToken);
}

/// Write the new credentials file to unpub-credentials.json
void writeNewCredentials(oauth2.Credentials credentials) {
  Credentials.pathToCredentials.write(credentials.toJson());
}

int _port = 42666;

/// Create a client with authorization.
Future<oauth2.Client> _clientWithAuthorization() async {
  final grant = oauth2.AuthorizationCodeGrant(
      _identifier, Uri.parse(_authEndpoint), Uri.parse(_tokenEndpoint),
      secret: _secret, basicAuth: false, httpClient: http.Client());

  final completer = Completer<oauth2.Client>();

  final localBaseUrl = 'http://localhost:$_port';

  await _waitForResponse(localBaseUrl, completer, grant);

  final authUrl =
      '${grant.getAuthorizationUrl(Uri.parse(localBaseUrl), scopes: _scopes)}'
      '&access_type=offline&approval_prompt=force';

  print('To login to Onepub.\n'
      'From a web browser, go to $authUrl\n'
      'When prompted click "Allow access".\n\n'
      'Waiting for your authorisation...');

  final client = await completer.future;
  print('Successfully authorised.\n');
  return client;
}

//
Future<void> _waitForResponse(
    String localBaseUrl,
    Completer<oauth2.Client> completer,
    oauth2.AuthorizationCodeGrant grant) async {
  final server = await bindServer(_port);
  shelf_io.serveRequests(server, (request) {
    if (request.url.path == 'authorised') {
      server.close();
      return shelf.Response.ok('Onepub successfully authorised.');
    }

    if (request.url.path.isNotEmpty) {
      /// Forbid all other requests.
      return shelf.Response.notFound('Invalid Request.');
    }

    print('Authorisation received, processing...');

    /// Redirect to authorised page.
    final resp = shelf.Response.found('$localBaseUrl/authorised');

    completer.complete(
        grant.handleAuthorizationResponse(queryToMap(request.url.query)));

    return resp;
  });
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
