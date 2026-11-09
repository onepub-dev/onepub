#! /usr/bin/env dcli

import 'dart:io';

import 'package:args/args.dart';
import 'package:dcli/dcli.dart' as dcli;
import 'package:onepub/src/util/one_pub_token_store.dart';

const betaHost = 'beta.onepub.dev';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('run-id', mandatory: true)
    ..addOption('id', mandatory: true)
    ..addOption('name', mandatory: true)
    ..addFlag('dry-run', negatable: false);
  final args = parser.parse(arguments);
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
  final uri = Uri.https(
      betaHost,
      '/api/test/organisation/close/${Uri.encodeComponent(id)}',
      {'name': name});
  if (args['dry-run'] as bool) {
    print('Would close disposable organisation $id ($name) on $betaHost.');
    return;
  }

  final credentials = await OnePubTokenStore().credentials;
  final matches = credentials
      .where((item) => item.url.scheme == 'https' && item.url.host == betaHost);
  if (matches.isEmpty) {
    throw StateError('No HTTPS beta credential found.');
  }
  final credential = matches.first;
  final token = credential.token ?? dcli.env[credential.env ?? ''];
  if (token == null || token.isEmpty) {
    throw StateError('Beta credential is incomplete.');
  }

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final request =
        await client.postUrl(uri).timeout(const Duration(seconds: 10));
    request.followRedirects = false;
    request.headers.set(HttpHeaders.authorizationHeader, token);
    request.headers
        .set(HttpHeaders.userAgentHeader, 'OnePub-beta-authorized-pentest/1.0');
    final response = await request.close().timeout(const Duration(seconds: 20));
    await response.drain<void>().timeout(const Duration(seconds: 20));
    if (response.statusCode != HttpStatus.ok) {
      throw StateError('Test organisation closure failed: HTTP '
          '${response.statusCode}.');
    }
    print('Test organisation closure recorded for $id ($name).');
  } finally {
    client.close(force: true);
  }
}
