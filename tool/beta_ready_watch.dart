#! /usr/bin/env dcli

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:dcli/dcli.dart' as dcli;
import 'package:onepub/src/util/one_pub_token_store.dart';
import 'package:pub_semver/pub_semver.dart';

import 'pen_test_target.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('version', mandatory: true)
    ..addOption('minutes', defaultsTo: '60')
    ..addOption('interval-seconds', defaultsTo: '60');
  final args = parser.parse(arguments);
  final targetVersion = Version.parse(args['version'] as String);
  final minutes = int.tryParse(args['minutes'] as String);
  final intervalSeconds = int.tryParse(args['interval-seconds'] as String);
  if (minutes == null || minutes < 1 || minutes > 480) {
    throw ArgumentError('--minutes must be 1..480.');
  }
  if (intervalSeconds == null ||
      intervalSeconds < 15 ||
      intervalSeconds > 300) {
    throw ArgumentError('--interval-seconds must be 15..300.');
  }

  final credentials = await OnePubTokenStore().credentials;
  final matches = credentials.where((item) => penTestTarget.owns(item.url));
  if (matches.isEmpty) {
    throw StateError('No credential found for the selected target.');
  }
  final credential = matches.first;
  final token = credential.token ?? dcli.env[credential.env ?? ''];
  if (token == null || token.isEmpty) {
    throw StateError('Target credential is incomplete.');
  }

  final deadline = DateTime.now().toUtc().add(Duration(minutes: minutes));
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5)
    ..idleTimeout = const Duration(seconds: 5);
  String? previous;
  print('Watching ${penTestTarget.url} for $targetVersion, '
      'at most $minutes minutes.');
  try {
    while (DateTime.now().toUtc().isBefore(deadline)) {
      try {
        final status = await check(client, '/api/status');
        final servedVersion = status.statusCode == HttpStatus.ok
            ? versionFromStatus(status.body)
            : null;
        final state = servedVersion == null
            ? 'HTTP ${status.statusCode}'
            : 'version $servedVersion';
        if (state != previous) {
          print('${DateTime.now().toUtc().toIso8601String()} $state');
          previous = state;
        }
        if (servedVersion == targetVersion) {
          final gate = await check(client, '/api/test/whoami', token: token);
          print('test endpoint: HTTP ${gate.statusCode}');
          if (gate.statusCode == HttpStatus.ok) {
            print('READY: $targetVersion and activation confirmed.');
          } else {
            print('DEPLOYED: activation is still needed.');
            exitCode = 3;
          }
          return;
        }
      } catch (error) {
        final state = 'temporary check error: ${error.runtimeType}';
        if (state != previous) {
          print('${DateTime.now().toUtc().toIso8601String()} $state');
          previous = state;
        }
      }
      await Future<void>.delayed(Duration(seconds: intervalSeconds));
    }
    print('TIMEOUT: $targetVersion was not observed during the watch window.');
    exitCode = 2;
  } finally {
    client.close(force: true);
  }
}

Future<({int statusCode, String body})> check(HttpClient client, String path,
    {String? token}) async {
  final uri = penTestTarget.uri(path);
  if (!penTestTarget.owns(uri)) {
    throw StateError('Beta target guard failed.');
  }
  final request = await client.getUrl(uri).timeout(const Duration(seconds: 8));
  request.followRedirects = false;
  request.headers
      .set(HttpHeaders.userAgentHeader, 'OnePub-beta-authorized-pentest/1.0');
  if (token != null) {
    request.headers.set(HttpHeaders.authorizationHeader, token);
  }
  final response = await request.close().timeout(const Duration(seconds: 15));
  final buffer = BytesBuilder();
  await for (final chunk in response.timeout(const Duration(seconds: 15))) {
    if (buffer.length + chunk.length > 16384) {
      throw StateError('Beta response exceeded the readiness size bound.');
    }
    buffer.add(chunk);
  }
  return (
    statusCode: response.statusCode,
    body: utf8.decode(buffer.takeBytes()),
  );
}

Version? versionFromStatus(String rawBody) {
  final envelope = jsonDecode(rawBody);
  if (envelope is! Map<String, dynamic>) {
    return null;
  }
  final body = envelope['body'] is Map<String, dynamic>
      ? envelope['body'] as Map<String, dynamic>
      : envelope;
  if (body['version'] is! String) {
    return null;
  }
  try {
    return Version.parse(body['version'] as String);
  } on FormatException {
    return null;
  }
}
