@Tags(['onepub_command', 'integration', 'staging'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:onepub/src/util/one_pub_token_store.dart';
import 'package:onepub/src/util/send_command.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../../fixture_oauth.dart';
import 'staging_common.dart';

Future<({int status, Map<String, dynamic> body})> _request(
    HttpClient client, Uri origin, String method, String path) async {
  final uri = origin.resolve(path);
  if (uri.scheme != origin.scheme ||
      uri.host != origin.host ||
      uri.port != origin.port) {
    throw StateError('CLI challenge request left staging origin.');
  }
  final request =
      await client.openUrl(method, uri).timeout(const Duration(seconds: 10));
  request.followRedirects = false;
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

Future<int> _complete(Uri origin, String challenge, String actor) async =>
    (await sendFixtureCommand(
      command: 'test/auth/completeCliLogin/$challenge',
      commandType: CommandType.cli,
      onepubUrl: origin.origin,
      actor: actor,
      method: Method.post,
    ))
        .status;

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
        final unknownComplete = await _complete(origin, unknown, token);
        expect(unknownComplete, HttpStatus.conflict);

        final challenge = const Uuid().v4();
        final waitPath = '/api/member/awaitLogin/$challenge';
        final first = await _request(client, origin, 'GET', waitPath);
        expect(first.status, HttpStatus.ok);
        expect(_challengeStatus(first.body), 'retry');

        final complete = await _complete(origin, challenge, token);
        expect(complete, HttpStatus.ok);
        final duplicate = await _complete(origin, challenge, token);
        expect(duplicate, HttpStatus.conflict);
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
        // Match the shipped five-minute browser completion window.
        await Future<void>.delayed(const Duration(minutes: 5, seconds: 1));
        final complete = await _complete(origin, challenge, token);
        expect(complete, HttpStatus.conflict);
        final expired = await _request(client, origin, 'GET', waitPath);
        expect(expired.status, HttpStatus.ok);
        expect(_challengeStatus(expired.body), 'timeout');
      } finally {
        client.close(force: true);
      }
    });
  }, timeout: const Timeout(Duration(minutes: 7)));
}
