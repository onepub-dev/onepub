@Tags(['onepub_command', 'integration', 'staging'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:onepub/src/util/one_pub_token_store.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'staging_common.dart';

Future<({int status, Map<String, dynamic> body})> _request(
    HttpClient client, Uri origin, String method, String path,
    {String? token}) async {
  final uri = origin.resolve(path);
  if (uri.scheme != origin.scheme ||
      uri.host != origin.host ||
      uri.port != origin.port) {
    throw StateError('CLI challenge request left staging origin.');
  }
  final request =
      await client.openUrl(method, uri).timeout(const Duration(seconds: 10));
  request.followRedirects = false;
  if (token != null) {
    request.headers.set(HttpHeaders.authorizationHeader, token);
  }
  final response = await request.close().timeout(const Duration(seconds: 20));
  final raw = await utf8.decoder
      .bind(response)
      .join()
      .timeout(const Duration(seconds: 20));
  final json = jsonDecode(raw);
  if (json is! Map<String, dynamic>) {
    throw StateError('CLI challenge response was not a JSON object.');
  }
  return (status: response.statusCode, body: json);
}

String? _challengeStatus(Map<String, dynamic> response) {
  final body = response['body'];
  return body is Map<String, dynamic> ? body['status'] as String? : null;
}

void main() {
  final config = StagingConfig.fromEnv();
  setUpAll(() => ensureTestUsers(config));

  test('CLI challenges reject unknown and duplicate completions', () async {
    await withAdmin(config, (_) async {
      final origin = Uri.parse(config.stagingUrl);
      final token = await OnePubTokenStore().load();
      final client = HttpClient();
      try {
        final unknown = const Uuid().v4();
        final unknownComplete = await _request(
            client, origin, 'POST', '/api/test/auth/completeCliLogin/$unknown',
            token: token);
        expect(unknownComplete.status, HttpStatus.conflict);

        final challenge = const Uuid().v4();
        final waitPath = '/api/member/awaitLogin/$challenge';
        final completePath = '/api/test/auth/completeCliLogin/$challenge';
        final first = await _request(client, origin, 'GET', waitPath);
        expect(first.status, HttpStatus.ok);
        expect(_challengeStatus(first.body), 'retry');

        final complete =
            await _request(client, origin, 'POST', completePath, token: token);
        expect(complete.status, HttpStatus.ok);
        final duplicate =
            await _request(client, origin, 'POST', completePath, token: token);
        expect(duplicate.status, HttpStatus.conflict);
        // Do not poll the completed challenge: that would mint an additional
        // System Administrator token in beta. The local dispatch test covers
        // successful delivery, while this beta test checks duplicate denial.
      } finally {
        client.close(force: true);
      }
    });
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('expired CLI challenge cannot be completed', () async {
    await withAdmin(config, (_) async {
      final origin = Uri.parse(config.stagingUrl);
      final token = await OnePubTokenStore().load();
      final client = HttpClient();
      try {
        final challenge = const Uuid().v4();
        final waitPath = '/api/member/awaitLogin/$challenge';
        final first = await _request(client, origin, 'GET', waitPath);
        expect(first.status, HttpStatus.ok);
        expect(_challengeStatus(first.body), 'retry');
        await Future<void>.delayed(const Duration(seconds: 61));
        final complete = await _request(client, origin, 'POST',
            '/api/test/auth/completeCliLogin/$challenge',
            token: token);
        expect(complete.status, HttpStatus.conflict);
        final expired = await _request(client, origin, 'GET', waitPath);
        expect(expired.status, HttpStatus.ok);
        expect(_challengeStatus(expired.body), 'timeout');
      } finally {
        client.close(force: true);
      }
    });
  }, timeout: const Timeout(Duration(minutes: 3)));
}
