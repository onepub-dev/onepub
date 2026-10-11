import 'dart:convert';
import 'dart:io';

import 'package:dcli_core/dcli_core.dart' as core;
import 'package:onepub/src/util/one_pub_token_store.dart';
import 'package:test/test.dart';

import 'test_settings.dart';

void main() {
  late HttpServer server;
  late String target;
  final requests = <String>[];

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    target = 'http://127.0.0.1:${server.port}';
    requests.clear();
    server.listen((request) async {
      requests.add(request.uri.path);
      expect(request.headers.value('authorization'), 'run-token');
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'body': {
          'email': 'run-admin@example.test',
          'firstname': 'Run',
          'lastname': 'Administrator',
          'roles': ['SystemAdministrator'],
          'organisationName': 'Run organisation',
          'obfuscateOrganisationId': 'run-org',
        },
      }));
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  Map<String, String> snapshot({String? url}) => {
        'onepubUrl': url ?? target,
        'loadTestUrl': url ?? target,
        'organisationId': 'run-org',
        'organisationName': 'Run organisation',
        'member': 'run-admin@example.test',
        'onepub_token': 'run-token',
      };

  test('nested setup keeps the validated run token without shared YAML',
      () async {
    await core.withEnvironmentAsync(() async {
      final settings = TestSettings();
      expect(settings.member, 'run-admin@example.test');
      expect(settings.organisationId, 'run-org');
      await withTestServer(() async {
        expect(await OnePubTokenStore().load(), 'run-token');
        // Staging setup nests TestUsers.init inside its outer token scope.
        await withTestServer(() async {
          expect(await OnePubTokenStore().load(), 'run-token');
        });
        expect(await OnePubTokenStore().load(), 'run-token');
      });
      expect(requests, [
        '/api/test/member/details/run-token',
        '/api/test/member/details/run-token',
      ]);
      expect(settings.save, throwsStateError);
    }, environment: {
      TestSettings.runSettingsEnvironmentKey: jsonEncode(snapshot()),
      'ONEPUB_STAGING_URL': target,
      'ONEPUB_TOKEN': 'unrelated-publishing-token',
    });
  });

  test('run snapshot still rejects production before making requests',
      () async {
    await core.withEnvironmentAsync(() async {
      expect(TestSettings.new, throwsStateError);
      expect(requests, isEmpty);
    }, environment: {
      TestSettings.runSettingsEnvironmentKey:
          jsonEncode(snapshot(url: 'https://onepub.dev')),
    });
  });

  test('malformed run snapshot fails closed without disclosing its content',
      () async {
    for (final content in [
      'secret-canary',
      '{"onepub_token":"secret-canary"}'
    ]) {
      await core.withEnvironmentAsync(() async {
        expect(
          TestSettings.new,
          throwsA(isA<StateError>().having(
            (error) => error.message,
            'message',
            'Invalid isolated system-test settings.',
          )),
        );
        expect(requests, isEmpty);
      }, environment: {TestSettings.runSettingsEnvironmentKey: content});
    }
  });
}
