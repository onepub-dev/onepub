#! /usr/bin/env dcli

import 'dart:async';
import 'dart:io';

import 'package:dcli/dcli.dart' as dcli;
import 'package:onepub/src/util/one_pub_token_store.dart';

import 'pen_test_target.dart';

Future<void> main() async {
  final credentials = await OnePubTokenStore().credentials;
  final matches = credentials.where((item) => penTestTarget.owns(item.url));
  if (matches.isEmpty) {
    throw StateError('No credential found for the selected target.');
  }
  final credential = matches.first;
  final token = credential.token ?? dcli.env[credential.env ?? ''];
  final segments = credential.url.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList();
  if (token == null ||
      token.isEmpty ||
      segments.length < 2 ||
      segments.first != 'api') {
    throw StateError('Target credential is incomplete.');
  }
  final organisation = segments[1];
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5)
    ..idleTimeout = const Duration(seconds: 5)
    ..maxConnectionsPerHost = 1;
  try {
    final cases = <({String name, Uri uri})>[
      (
        name: 'baseline organisation lookup',
        uri: penTestTarget.uri('/api/organisation/details/$organisation'),
      ),
      (
        name: 'organisation quote canary',
        uri: penTestTarget.uri("/api/organisation/details/'"),
      ),
      (
        name: 'organisation SQL-style canary',
        uri: penTestTarget.uri("/api/organisation/details/' OR '1'='1"),
      ),
      (
        name: 'package quote canary',
        uri: penTestTarget.uri("/api/$organisation/api/packages/'"),
      ),
      (
        name: 'package SQL-style canary',
        uri: penTestTarget.uri("/api/$organisation/api/packages/' OR '1'='1"),
      ),
      (
        name: 'package encoded-null canary',
        uri: penTestTarget.encodedPath('/api/$organisation/api/packages/%00'),
      ),
    ];
    for (final item in cases) {
      final result = await probe(client, item.uri, token);
      print('${item.name}: HTTP ${result.statusCode} ${result.type}');
      if (item.name != 'baseline organisation lookup' &&
          result.statusCode == HttpStatus.ok &&
          result.type == 'application/json') {
        print('REVIEW: an injection canary returned JSON 200.');
        exitCode = 2;
      }
      if (result.statusCode >= 500) {
        exitCode = 2;
      }
    }
  } finally {
    client.close(force: true);
  }
}

Future<({int statusCode, String type})> probe(
    HttpClient client, Uri uri, String token) async {
  if (!penTestTarget.owns(uri)) {
    throw StateError('Beta target guard failed.');
  }
  final request = await client.getUrl(uri).timeout(const Duration(seconds: 10));
  request.followRedirects = false;
  request.headers.set(HttpHeaders.authorizationHeader, token);
  request.headers
      .set(HttpHeaders.userAgentHeader, 'OnePub-beta-authorized-pentest/1.0');
  final response = await request.close().timeout(const Duration(seconds: 15));
  final type = response.headers.contentType?.mimeType ?? 'unknown';
  await response.drain<void>().timeout(const Duration(seconds: 15));
  return (statusCode: response.statusCode, type: type);
}
