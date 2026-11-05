import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'scim_test_client.dart';

void main() {
  late HttpServer server;
  late ScimTestClient client;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = ScimTestClient(
      onepubUrl: 'http://127.0.0.1:${server.port}',
      clientId: 'fixture:client',
      clientSecret: 'secret+canary',
    );
  });
  tearDown(() => server.close(force: true));

  test('uses OAuth credentials and paginates more than 100 SCIM users',
      () async {
    var tokenRequests = 0;
    final starts = <int>[];
    server.listen((request) async {
      expect(request.uri.query, isNot(contains('secret')));
      if (request.uri.path == '/api/provisioning/oauth/token') {
        tokenRequests++;
        expect(request.method, 'POST');
        final encoded =
            base64Encode(utf8.encode('fixture%3Aclient:secret%2Bcanary'));
        expect(request.headers.value(HttpHeaders.authorizationHeader),
            'Basic $encoded');
        final form =
            Uri.splitQueryString(await utf8.decoder.bind(request).join());
        expect(form, {'grant_type': 'client_credentials', 'scope': 'scim'});
        await _reply(request, {
          'access_token': 'scim-only-token',
          'token_type': 'Bearer',
          'expires_in': 300,
        });
        return;
      }
      expect(request.uri.path, '/api/scim/v2/Users');
      expect(request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer scim-only-token');
      expect(request.uri.queryParameters['filter'],
          'userName eq "test+user@example.test"');
      final start = int.parse(request.uri.queryParameters['startIndex']!);
      starts.add(start);
      await _reply(request, {
        'totalResults': 105,
        'startIndex': start,
        'itemsPerPage': start == 1 ? 100 : 5,
        'Resources': List.generate(
            start == 1 ? 100 : 5, (index) => {'id': 'user-${start + index}'}),
      });
    });

    final users = await client.findUsers('test+user@example.test');
    expect(users, hasLength(105));
    expect(users.last['id'], 'user-105');
    expect(starts, [1, 101]);
    expect(tokenRequests, 1);
  });

  test('new users carry no roles or credentials; active PATCH uses stable ID',
      () async {
    final bodies = <Map<String, dynamic>>[];
    server.listen((request) async {
      if (request.uri.path == '/api/provisioning/oauth/token') {
        await _reply(request, {
          'access_token': 'scim-only-token',
          'token_type': 'Bearer',
          'expires_in': 300,
        });
        return;
      }
      bodies.add(jsonDecode(await utf8.decoder.bind(request).join())
          as Map<String, dynamic>);
      if (request.method == 'POST') {
        expect(request.uri.path, '/api/scim/v2/Users');
      } else {
        expect(request.method, 'PATCH');
        expect(request.uri.path, '/api/scim/v2/Users/stable-id');
      }
      await _reply(request, {'id': 'stable-id'});
    });
    final user = await client.createUser(
        email: 'person@example.test', firstname: 'Test', lastname: 'Person');
    await client.setActive(user['id'] as String, active: false);
    expect(bodies.first, {
      'schemas': [ScimTestClient.userSchema],
      'userName': 'person@example.test',
      'name': {'givenName': 'Test', 'familyName': 'Person'},
      'active': true,
    });
    expect(bodies.last['Operations'], [
      {'op': 'replace', 'path': 'active', 'value': false}
    ]);
  });

  test('does not follow credential redirects or expose server diagnostics',
      () async {
    var count = 0;
    server.listen((request) async {
      count++;
      request.response.statusCode = HttpStatus.temporaryRedirect;
      request.response.headers.set(HttpHeaders.locationHeader,
          'http://127.0.0.1:${server.port}/capture');
      request.response.write('secret+canary server internal diagnostic');
      await request.response.close();
    });
    await expectLater(
      client.findUsers('person@example.test'),
      throwsA(isA<ScimTestException>().having((error) => error.toString(),
          'sanitized error', 'SCIM request failed. HTTP 307')),
    );
    expect(count, 1);
  });

  test('rejects unsafe destinations before authentication', () {
    expect(
      () => ScimTestClient(
          onepubUrl: 'https://onepub.dev',
          clientId: 'client',
          clientSecret: 'secret'),
      throwsStateError,
    );
  });
}

Future<void> _reply(HttpRequest request, Map<String, dynamic> body) async {
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(body));
  await request.response.close();
}
