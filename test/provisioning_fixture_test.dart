import 'dart:convert';
import 'dart:io';

import 'package:dcli_core/dcli_core.dart' as core;
import 'package:onepub/src/onepub_settings.dart';
import 'package:onepub/src/util/one_pub_token_store.dart';
import 'package:test/test.dart';

import 'provisioning_fixture.dart';

void main() {
  test('human role setup follows real SCIM and uses separate fixture auth',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final paths = <String>[];
    server.listen((request) async {
      paths.add(request.uri.path);
      request.response.headers.contentType = ContentType.json;
      final path = request.uri.path;
      if (path.startsWith('/api/test/')) {
        expect(request.headers.value(HttpHeaders.authorizationHeader),
            'bootstrap-member-token');
      }
      if (path == '/api/test/provisioning/bootstrap') {
        expect(request.method, 'POST');
        request.response.write(jsonEncode({
          'body': {'clientId': 'client', 'clientSecret': 'secret'}
        }));
      } else if (path == '/api/provisioning/oauth/token') {
        expect(request.headers.value(HttpHeaders.authorizationHeader),
            'Basic ${base64Encode(utf8.encode('client:secret'))}');
        request.response.write(jsonEncode({
          'access_token': 'provisioning-token',
          'token_type': 'Bearer',
          'expires_in': 300,
        }));
      } else if (path == '/api/scim/v2/Users') {
        expect(request.headers.value(HttpHeaders.authorizationHeader),
            'Bearer provisioning-token');
        if (request.method == 'GET') {
          request.response
              .write(jsonEncode({'totalResults': 0, 'Resources': <dynamic>[]}));
        } else {
          final body = jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>;
          expect(body.containsKey('roles'), isFalse);
          expect(body['userName'], 'human@example.test');
          request.response.statusCode = HttpStatus.created;
          request.response.write(jsonEncode({'id': 'scim-user'}));
        }
      } else if (path == '/api/test/provisioning/bind' ||
          path == '/api/test/provisioning/service-account') {
        final body = jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>;
        final human = path.endsWith('/bind');
        expect(body['role'], human ? 'Administrator' : 'CICD');
        if (human) {
          expect(body, {'scimId': 'scim-user', 'role': 'Administrator'});
        }
        request.response.write(jsonEncode({
          'body': {
            'email': human ? 'human@example.test' : 'ci@example.test',
            'firstname': 'Test',
            'lastname': 'Identity',
            'roles': [body['role']],
            'organisationName': 'Test organisation',
            'obfuscateOrganisationId': 'test-org',
          }
        }));
      } else {
        fail('Unexpected fixture path: $path');
      }
      await request.response.close();
    });

    await core.withTempDirAsync((directory) async {
      await OnePubSettings.withPathTo(directory, () async {
        final settings = OnePubSettings.use()
          ..onepubUrl = 'http://127.0.0.1:${server.port}'
          ..obfuscatedOrganisationId = 'test-org';
        await OnePubTokenStore.withPathTo(directory, () async {
          await OnePubTokenStore().addToken(
              onepubApiUrl: settings.onepubApiUrlAsString,
              onepubToken: 'bootstrap-member-token');
          final fixture = ProvisioningFixture();
          final human = await fixture.createMember(
              userEmail: 'human@example.test',
              firstname: 'Test',
              lastname: 'Identity',
              role: 'Administrator');
          expect(human.success, isTrue);
          expect(human.role, 'Administrator');
          expect(human.errorMessage, isNull);
          final ci = await fixture.createMember(
              userEmail: 'ci@example.test',
              firstname: 'Test',
              lastname: 'Identity',
              role: 'CICD');
          expect(ci.success, isTrue);
          expect(ci.role, 'CICD');
        });
      });
    });
    expect(paths, [
      '/api/test/provisioning/bootstrap',
      '/api/provisioning/oauth/token',
      '/api/scim/v2/Users',
      '/api/scim/v2/Users',
      '/api/test/provisioning/bind',
      '/api/test/provisioning/service-account',
    ]);
  });
}
