import 'dart:convert';
import 'dart:io';

import 'package:dcli_core/dcli_core.dart' as core;
import 'package:onepub/src/exceptions.dart';
import 'package:onepub/src/util/role_enum.dart';
import 'package:test/test.dart';

import 'test_settings.dart';
import 'test_users.dart';

void main() {
  late HttpServer server;
  late String target;
  var exports = 0;
  var creations = 0;
  var lookups = 0;
  var denied = false;
  const email = 'raced@example.test';

  setUp(() async {
    exports = creations = lookups = 0;
    denied = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    target = assertSafeOnePubTestUrl('http://127.0.0.1:${server.port}');
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      Object body;
      if (request.uri.path.contains('/exportToken/')) {
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
      } else if (request.uri.path.endsWith('/create')) {
        creations++;
        expect(request.uri.queryParameters['email'], email);
        request.response.statusCode = 409;
        body = {
          'error': {'message': 'Member already exists'}
        };
      } else if (request.uri.path.endsWith('/details/raced-token')) {
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
  tearDown(() => server.close(force: true));

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
            expect(lookups, 1);
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
