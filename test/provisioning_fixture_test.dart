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
    var exchanges = 0;
    server.listen((request) async {
      paths.add(request.uri.path);
      request.response.headers.contentType = ContentType.json;
      final path = request.uri.path;
      Map<String, dynamic>? fixtureBody;
      if (path == '/api/scim/v2/TestProvisioningFixtures') {
        expect(request.headers.value(HttpHeaders.authorizationHeader),
            'Bearer bootstrap-member-token');
        fixtureBody = jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>;
        expect(fixtureBody['schemas'],
            ['urn:onepub:params:scim:schemas:test:2.0:Fixture']);
      }
      if (path == '/api/scim/v2/TestOrganisations') {
        expect(request.method, 'POST');
        expect(request.headers.value(HttpHeaders.authorizationHeader),
            'Bearer bootstrap-member-token');
        expect(jsonDecode(await utf8.decoder.bind(request).join()), {
          'schemas': ['urn:onepub:params:scim:schemas:test:2.0:Organisation'],
          'name': 'onepub_test_organisation',
          'plan': 'team',
          'dedicatedOwner': true,
        });
        request.response.write(jsonEncode({
          'schemas': ['urn:onepub:params:scim:schemas:test:2.0:Organisation'],
          'id': 'organisation-guid',
          'obfuscatedId': 'test-org',
          'organisationName': 'onepub_test_organisation',
          'operatorEmail': 'owner@example.test',
          'plan': 'team',
          'onepubToken': 'new-owner-token',
        }));
      } else if (fixtureBody?['operation'] == 'bootstrap') {
        expect(request.method, 'POST');
        expect(fixtureBody?['advancedClientCredentials'], false);
        request.response.write(jsonEncode({
          'schemas': ['urn:onepub:params:scim:schemas:test:2.0:Fixture'],
          'id': 'test-org',
          'roleGroups': {
            'Collaborator': 'collaborators',
            'TeamLeader': 'leaders',
            'Uploader': 'uploaders',
          },
        }));
      } else if (path == '/api/provisioning/oauth/token') {
        expect(request.headers.value(HttpHeaders.authorizationHeader),
            'Basic ${base64Encode(utf8.encode('client:secret'))}');
        final form =
            Uri.splitQueryString(await utf8.decoder.bind(request).join());
        expect(form['grant_type'],
            exchanges == 0 ? 'authorization_code' : 'refresh_token');
        exchanges++;
        request.response.write(jsonEncode({
          'access_token': 'provisioning-token',
          'refresh_token': 'refresh-$exchanges',
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
      } else if (path.startsWith('/api/scim/v2/Groups/')) {
        expect(request.method, 'PATCH');
        expect(request.headers.value(HttpHeaders.authorizationHeader),
            'Bearer provisioning-token');
        final body = jsonDecode(await utf8.decoder.bind(request).join());
        expect(body, {
          'schemas': ['urn:ietf:params:scim:api:messages:2.0:PatchOp'],
          'Operations': [
            {
              'op': 'add',
              'path': 'members',
              'value': [
                {'value': 'scim-user'}
              ]
            },
          ],
        });
        request.response.write(jsonEncode({'id': path.split('/').last}));
      } else if (fixtureBody?['operation'] == 'bind' ||
          fixtureBody?['operation'] == 'service-account') {
        final body = fixtureBody!;
        final human = body['operation'] == 'bind';
        expect(
            body['role'],
            isIn(human
                ? ['Administrator', 'Collaborator', 'TeamLeader', 'Uploader']
                : ['CICD']));
        if (human) {
          expect(body['scimId'], 'scim-user');
        }
        request.response.write(jsonEncode({
          'schemas': ['urn:onepub:params:scim:schemas:test:2.0:Fixture'],
          'id': 'fixture-member',
          'email': human ? 'human@example.test' : 'ci@example.test',
          'firstname': 'Test',
          'lastname': 'Identity',
          'roles': [body['role']],
          'organisationName': 'Test organisation',
          'obfuscateOrganisationId': 'test-org',
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
          final fixture = ProvisioningFixture(browserAuthorization: {
            'clientId': 'client',
            'clientSecret': 'secret',
            'authorizationCode': 'browser-code',
            'redirectUri': 'http://127.0.0.1:45678/callback',
          });
          final organisation = await fixture.createOrganisation(
              name: 'onepub_test_organisation', plan: 'team');
          expect(organisation['obfuscatedId'], 'test-org');
          expect(organisation['plan'], 'team');
          final human = await fixture.createMember(
              userEmail: 'human@example.test',
              firstname: 'Test',
              lastname: 'Identity',
              role: 'Administrator');
          expect(human.success, isTrue);
          expect(human.role, 'Administrator');
          expect(human.errorMessage, isNull);
          for (final role in ['Collaborator', 'TeamLeader', 'Uploader']) {
            final mapped = await fixture.createMember(
                userEmail: 'human@example.test',
                firstname: 'Test',
                lastname: 'Identity',
                role: role);
            expect(mapped.success, isTrue);
            expect(mapped.role, role);
          }
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
      '/api/scim/v2/TestOrganisations',
      '/api/scim/v2/TestProvisioningFixtures',
      '/api/provisioning/oauth/token',
      '/api/provisioning/oauth/token',
      '/api/scim/v2/Users',
      '/api/scim/v2/Users',
      '/api/scim/v2/TestProvisioningFixtures',
      for (final group in ['collaborators', 'leaders', 'uploaders']) ...[
        '/api/scim/v2/Users',
        '/api/scim/v2/Users',
        '/api/scim/v2/Groups/$group',
        '/api/scim/v2/TestProvisioningFixtures',
      ],
      '/api/scim/v2/TestProvisioningFixtures',
    ]);
  });
}
