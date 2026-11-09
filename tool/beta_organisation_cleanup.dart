#! /usr/bin/env dcli

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:dcli/dcli.dart' show green;

import '../test/fixture_oauth.dart';
import 'pen_test_target.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('target', defaultsTo: 'https://beta.onepub.dev')
    ..addOption('run-id', mandatory: true)
    ..addOption('id', mandatory: true)
    ..addOption('name', mandatory: true)
    ..addFlag('dry-run', negatable: false);
  final args = parser.parse(arguments);
  selectPenTestTarget(args['target'] as String);
  final runId = args['run-id'] as String;
  final id = args['id'] as String;
  final name = args['name'] as String;
  if (!RegExp(r'^[a-z0-9_]{1,20}$').hasMatch(runId) ||
      !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id) ||
      !RegExp(r'^onepub_staging_test_[a-z0-9_]+$').hasMatch(name) ||
      !name.contains('_${runId}_')) {
    throw ArgumentError('Provide the exact disposable organisation ID, name, '
        'and matching run ID from the run ledger.');
  }
  final uri = penTestTarget.uri('/api/scim/v2/TestOrganisations');
  if (args['dry-run'] as bool) {
    print('Would close disposable organisation $id ($name) '
        'on ${penTestTarget.url}.');
    return;
  }

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  FixtureOAuthBroker? broker;
  try {
    if (Platform.environment.containsKey(FixtureOAuth.authorizationKey)) {
      broker = await FixtureOAuth.startHarness(penTestTarget.url);
    }
    final token =
        await FixtureOAuth.token(root: true, onepubUrl: penTestTarget.url);
    final request =
        await client.postUrl(uri).timeout(const Duration(seconds: 10));
    request.followRedirects = false;
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({
      'schemas': ['urn:onepub:params:scim:schemas:test:2.0:Organisation'],
      'operation': 'close',
      'obfuscatedId': id,
      'name': name,
    }));
    request.headers
        .set(HttpHeaders.userAgentHeader, 'OnePub-beta-authorized-pentest/1.0');
    final response = await request.close().timeout(const Duration(seconds: 20));
    if (response.statusCode != HttpStatus.ok) {
      throw StateError('Test organisation closure failed: HTTP '
          '${response.statusCode}.');
    }
    final bytes = <int>[];
    await (() async {
      await for (final chunk in response) {
        if (bytes.length + chunk.length > 1024 * 1024) {
          throw StateError('Cleanup response exceeded the size limit.');
        }
        bytes.addAll(chunk);
      }
    })()
        .timeout(const Duration(seconds: 20));
    final body = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (body['obfuscatedId'] != id ||
        body['organisationName'] != name ||
        body['pendingClosure'] != true) {
      throw StateError('Test organisation closure was not confirmed.');
    }
    print(green('Test organisation closure recorded for $id ($name).'));
  } finally {
    client.close(force: true);
    await broker?.close();
  }
}
