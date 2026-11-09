import 'dart:convert';
import 'dart:io';

import 'package:dcli_core/dcli_core.dart' as core;
import 'package:onepub/src/onepub_settings.dart';
import 'package:test/test.dart';

import '../../../fixture_oauth.dart';
import '../../../provisioning_fixture.dart';
import 'staging_common.dart';

void main() {
  test('disposable organisation names identify each recurring run', () {
    expect(
      stagingTestOrganisationName('free', 12345, '20261103_a'),
      'onepub_staging_test_download_limit_free_20261103_a_12345',
    );
    expect(
      stagingTestOrganisationName('free', 12345, null),
      'onepub_staging_test_download_limit_free_12345',
    );
    expect(
      () => stagingTestOrganisationName('free', 12345, 'invalid/directory'),
      throwsArgumentError,
    );
  });

  test('cleanup uses fixture OAuth and confirms exact organisation', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    addTearDown(FixtureOAuth.reset);
    final origin = 'http://127.0.0.1:${server.port}';
    FixtureOAuth.configure(origin, {
      'onepubUrl': origin,
      'clientId': 'test-client',
      'clientSecret': 'test-secret',
      'refreshToken': 'test-refresh',
      'onepubToken': 'actor-selector',
      'scopes': 'test:fixtures',
    });
    var mismatch = false;
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/api/provisioning/oauth/token') {
        await request.drain<void>();
        request.response.write(
          jsonEncode({
            'access_token': 'fixture-access',
            'refresh_token': 'next-refresh',
            'token_type': 'Bearer',
            'expires_in': 300,
            'scope': 'test:fixtures',
          }),
        );
      } else {
        expect(request.uri.path, '/api/scim/v2/TestOrganisations');
        expect(request.method, 'POST');
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer fixture-access',
        );
        expect(jsonDecode(await utf8.decoder.bind(request).join()), {
          'schemas': ['urn:onepub:params:scim:schemas:test:2.0:Organisation'],
          'operation': 'close',
          'obfuscatedId': 'abc-123',
          'name': 'onepub_test_cleanup',
        });
        request.response.write(
          jsonEncode({
            'obfuscatedId': mismatch ? 'different' : 'abc-123',
            'organisationName': 'onepub_test_cleanup',
            'pendingClosure': true,
          }),
        );
      }
      await request.response.close();
    });
    await core.withTempDirAsync((directory) async {
      await OnePubSettings.withPathTo(directory, () async {
        OnePubSettings.use().onepubUrl = origin;
        final fixture = ProvisioningFixture();
        await fixture.closeOrganisation(
          id: 'abc-123',
          name: 'onepub_test_cleanup',
        );
        mismatch = true;
        await expectLater(
          fixture.closeOrganisation(id: 'abc-123', name: 'onepub_test_cleanup'),
          throwsException,
        );
      });
    });
  });
}
