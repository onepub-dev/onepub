#! /usr/bin/env dcli

import 'dart:io';

import 'package:args/args.dart';

import 'pen_test_target.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()..addFlag('heavy', negatable: false);
  final options = parser.parse(arguments);
  final heavy = options['heavy'] as bool;
  final cases = <String, String>{
    'baseline': 'onepub',
    'quote': '"onepub" OR "private"',
    'wildcards': 'lib_ * ?',
    'punctuation': r'()[]{}:~^\\',
    'unicode': 'pаckage café 漢字',
    'many-terms': List.filled(100, 'term').join(' '),
    'long-term': 'a' * 1024,
    if (heavy)
      'clause-flood': List.generate(1100, (index) => 't$index').join(' '),
    if (heavy) 'long-expression': 'a' * 20000,
  };
  print('Search input probe: ${DateTime.now().toUtc().toIso8601String()} '
      'heavy=$heavy');
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5)
    ..maxConnectionsPerHost = 2;
  var failures = 0;
  try {
    for (final entry in cases.entries) {
      final uri = penTestTarget.uri('/search', {'query': entry.value});
      if (!penTestTarget.owns(uri)) {
        throw StateError('Target guard failed.');
      }
      final watch = Stopwatch()..start();
      try {
        final request =
            await client.getUrl(uri).timeout(const Duration(seconds: 10));
        request.followRedirects = false;
        request.headers.set(
            HttpHeaders.userAgentHeader, 'OnePub-beta-authorized-pentest/1.0');
        final response =
            await request.close().timeout(const Duration(seconds: 30));
        final status = response.statusCode;
        await response.drain<void>().timeout(const Duration(seconds: 30));
        watch.stop();
        print('${entry.key}: status=$status '
            'elapsedMs=${watch.elapsedMilliseconds}');
        if (status >= 500) {
          failures++;
        }
      } catch (error) {
        watch.stop();
        print('${entry.key}: error=${error.runtimeType} '
            'elapsedMs=${watch.elapsedMilliseconds}');
        failures++;
      }
    }
  } finally {
    client.close(force: true);
  }
  print('Cases requiring review: $failures/${cases.length}');
  if (failures > 0) {
    exitCode = 2;
  }
}
