import 'dart:convert';
import 'dart:io';

import 'package:onepub/src/device/device_session.dart';
import 'package:onepub/src/onepub_settings.dart';
import 'package:onepub/src/util/login_persistence.dart';
import 'package:onepub/src/util/one_pub_token_store.dart';
import 'package:test/test.dart';

import 'login_preferences_test.dart' show completed;

class ChallengeSession extends DeviceSession {
  final Map<String, dynamic> payload;
  ChallengeSession(this.payload)
      : super(Uri.parse('https://example.test/api/org/'), 'device-1',
            Directory('/nonexistent'));
  @override
  Future<Map<String, dynamic>> post(
          String endpoint, Map<String, dynamic> body) async =>
      {
        'challengeId': 'challenge-1',
        'challenge': deviceBase64(utf8.encode(jsonEncode(payload)))
      };
}

void main() {
  test('public acquisition refuses the internal CLI operation', () async {
    final session = ChallengeSession({});
    await expectLater(
        session.acquire({'operation': 'cli'}), throwsFormatException);
  });

  test('challenge fields are checked before accessing the private key',
      () async {
    for (final altered in <String, Object?>{
      'domain': 'other',
      'deviceId': 'other',
      'repository-url': 'https://evil.test/api/org/',
      'operation': 'publish',
      'package': 'other',
      'version': '1.0.0',
      'nonce': '',
    }.entries) {
      final payload = <String, dynamic>{
        'domain': 'onepub-device-grant-v1',
        'deviceId': 'device-1',
        'repository-url': 'https://example.test/api/org/',
        'operation': 'read',
        'package': 'example',
        'nonce': 'nonce',
        altered.key: altered.value
      };
      await expectLater(
          ChallengeSession(payload)
              .acquire({'operation': 'read', 'package': 'example'}),
          throwsFormatException);
    }
  });

  test('proof scope excludes other origins, tenants, queries and traversal',
      () async {
    final session = ChallengeSession({});
    for (final target in [
      'https://evil.test/api/org/api/packages/example',
      'https://example.test/api/other/api/packages/example',
      'https://example.test/api/org/api/packages/example?query=1',
      'https://example.test/api/org/%2e%2e/other/',
      'https://example.test/api/member/logout'
    ]) {
      await expectLater(
          session.prove({'uri': target, 'method': 'GET', 'token': 'token'}),
          throwsFormatException);
    }
    expect(
        session.permitsCli(Uri.parse('https://example.test/api/member/logout')),
        isTrue);
    expect(session.permitsCli(Uri.parse('https://evil.test/api/member/logout')),
        isFalse);
    expect(
        session.permitsCli(Uri.parse('https://example.test/api/admin/delete')),
        isFalse);
  });

  test(
      'device login preserves other repositories and stores only public metadata',
      () async {
    final directory = await Directory.systemTemp.createTemp('device-login-');
    addTearDown(() => directory.delete(recursive: true));
    final settings =
        OnePubSettings(pathToSettings: '${directory.path}/onepub.yaml')
          ..onepubUrl = 'http://localhost:58080';
    await settings.save();
    await OnePubTokenStore.withPathTo('${directory.path}/tokens', () async {
      final tokens = File('${directory.path}/tokens/pub-tokens.json');
      await tokens.writeAsString(jsonEncode({
        'version': 1,
        'hosted': [
          {'url': 'http://localhost:58080/api/other/', 'token': 'keep'},
          {'url': 'http://localhost:58080/api/org-123/', 'token': 'replace'},
        ]
      }));
      final response = completed()
        ..deviceEnrollment = {
          'deviceId': 'device-1',
          'repositoryUrl': 'http://localhost:58080/api/org-123/'
        };
      await LoginPersistence(settings)
          .save(response, deviceStorage: Directory('${directory.path}/key'));
      final entries =
          (jsonDecode(await tokens.readAsString()) as Map)['hosted'] as List;
      expect(entries.length, 2);
      expect((entries.first as Map)['token'], 'keep');
      expect((entries.last as Map).containsKey('token'), isFalse);
      expect((entries.last as Map)['authHelper'], isA<List<dynamic>>());
      final session = await DeviceSession.load(
          settings, Uri.parse('http://localhost:58080/api/org-123/'));
      expect(session!.deviceId, 'device-1');
      expect(await DeviceSession.registry(settings).readAsString(),
          isNot(contains('not-a-real-token')));
    });
  });
}
