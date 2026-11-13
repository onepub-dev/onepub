import 'dart:convert';
import 'dart:io';

import 'package:dcli_core/dcli_core.dart' as core;
import 'package:onepub/src/exceptions.dart';
import 'package:onepub/src/util/role_enum.dart';
import 'package:test/test.dart';

import 'fixture_oauth.dart';
import 'test_settings.dart';
import 'test_users.dart';

void main() {
  late HttpServer server;
  late String target;
  var exports = 0;
  var creations = 0;
  var lookups = 0;
  var userQueries = 0;
  var denied = false;
  const email = 'raced@example.test';

  setUp(() async {
    exports = creations = lookups = 0;
    userQueries = 0;
    denied = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    target = assertSafeOnePubTestUrl('http://127.0.0.1:${server.port}');
    FixtureOAuth.configure(target, {
      'onepubUrl': target,
      'clientId': 'fixture-client',
      'clientSecret': 'fixture-secret',
      'refreshToken': 'fixture-refresh',
      'onepubToken': 'bootstrap-token',
      'scopes': 'scim test:fixtures',
    });
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      Object body;
      if (request.uri.path == '/api/provisioning/oauth/token') {
        final form =
            Uri.splitQueryString(await utf8.decoder.bind(request).join());
        final fixture = form['refresh_token'] == 'fixture-refresh';
        body = {
          'access_token': fixture ? 'fixture-access' : 'scim-access',
          'refresh_token': fixture ? 'fixture-next' : 'scim-next',
          'token_type': 'Bearer',
          'expires_in': 300,
          'scope': fixture ? 'scim test:fixtures' : 'scim'
        };
      } else if (request.uri.path.contains('/exportToken/')) {
        expect(request.headers.value(HttpHeaders.authorizationHeader),
            'Bearer fixture-access');
        exports++;
        if (denied || exports == 1) {
          request.response.statusCode = denied ? 403 : 404;
          body = {
            'error': {
              'message': denied
                  ? 'Forbidden'
                  : '$email does not exist in Organisation Fixture.'
            }
          };
        } else {
          body = {
            'body': {'onepubToken': 'raced-token'}
          };
        }
      } else if (request.uri.path == '/api/scim/v2/TestProvisioningFixtures') {
        expect(request.headers.value(HttpHeaders.authorizationHeader),
            'Bearer fixture-access');
        final input = jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>;
        if (input['operation'] == 'bootstrap') {
          body = {
            'roleGroups': {
              'Collaborator': 'collaborators',
              'TeamLeader': 'leaders',
              'Uploader': 'uploaders'
            }
          };
        } else {
          expect(input['operation'], 'bind');
          expect(input['scimId'], 'raced-scim-id');
          body = {
            'email': email,
            'firstname': 'Raced',
            'lastname': 'Member',
            'roles': ['Administrator'],
            'organisationName': 'Fixture',
            'obfuscateOrganisationId': 'fixture-org'
          };
        }
      } else if (request.uri.path == '/api/scim/v2/Users') {
        expect(request.headers.value(HttpHeaders.authorizationHeader),
            'Bearer fixture-access');
        if (request.method == 'GET') {
          userQueries++;
          body = {
            'totalResults': userQueries == 1 ? 0 : 1,
            'Resources': userQueries == 1
                ? <dynamic>[]
                : [
                    {'id': 'raced-scim-id', 'userName': email}
                  ]
          };
        } else {
          expect(request.method, 'POST');
          creations++;
          final input = jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>;
          expect(input['userName'], email);
          request.response.statusCode = HttpStatus.conflict;
          body = {
            'schemas': ['urn:ietf:params:scim:api:messages:2.0:Error'],
            'status': '409',
            'scimType': 'uniqueness'
          };
        }
      } else if (request.uri.path == '/api/member/whoami') {
        lookups++;
        body = {
          'body': {
            'email': email,
            'firstname': 'Raced',
            'lastname': 'Member',
            'roles': ['Administrator'],
            'organisationName': 'Fixture',
            'obfuscateOrganisationId': 'fixture-org',
          }
        };
      } else {
        request.response.statusCode = 500;
        body = {
          'error': {'message': 'Unexpected fixture request'}
        };
      }
      request.response.write(jsonEncode(body));
      await request.response.close();
    });
  });
  tearDown(() async {
    FixtureOAuth.reset();
    await server.close(force: true);
  });

  Future<void> scoped(Future<void> Function() action) =>
      core.withEnvironmentAsync(
          () => withTestServer(action, resolveOrganisationToken: false),
          environment: {
            TestSettings.runSettingsEnvironmentKey: jsonEncode({
              'onepubUrl': target,
              'loadTestUrl': target,
              'organisationId': 'fixture-org',
              'organisationName': 'Fixture',
              'member': 'bootstrap@example.test',
              'onepub_token': 'bootstrap-token',
            }),
            'ONEPUB_STAGING_URL': target,
          });

  test(
      'creation race resolves the existing member without a fallback user',
      () => scoped(() async {
            final member =
                await TestUsers(init: true).createAdministrator(email);
            expect(member.email, email);
            expect(member.onepubToken, 'raced-token');
            expect(member.roles, {RoleEnum.Administrator});
            expect(exports, 2);
            expect(creations, 1);
            expect(userQueries, 2);
            expect(lookups, 0);
          }));

  test(
      'denied lookup never attempts member creation',
      () => scoped(() async {
            denied = true;
            await expectLater(TestUsers(init: true).createAdministrator(email),
                throwsA(isA<APIException>()));
            expect(exports, 1);
            expect(creations, 0);
            expect(lookups, 0);
          }));
}
