import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/beta_ready_watch.dart' as readiness;
import '../../../tool/pen_test_target.dart';
import '../../fixture_oauth.dart';
import '../../test_settings.dart';

void main() {
  test('explicit custom fixture origin stays pinned to selected target', () {
    selectPenTestTarget('https://pentest.example:8443');
    addTearDown(() => selectPenTestTarget('https://beta.onepub.dev'));
    expect(assertSafeOnePubTestUrl('https://pentest.example:8443'),
        'https://pentest.example:8443');
    expect(() => assertSafeOnePubTestUrl('https://pentest.example:8444'),
        throwsStateError);
    expect(
        () => assertSafeOnePubTestUrl('https://onepub.dev'), throwsStateError);
  });

  test('fixture readiness exchanges OAuth and never sends the member token',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = HttpClient();
    final origin = 'http://127.0.0.1:${server.port}';
    selectPenTestTarget(origin);
    FixtureOAuth.configure(origin, {
      'onepubUrl': origin,
      'clientId': 'client',
      'clientSecret': 'secret',
      'refreshToken': 'refresh',
      'onepubToken': 'member-selector',
      'scopes': 'test:fixtures',
    });
    addTearDown(() async {
      FixtureOAuth.reset();
      selectPenTestTarget('https://beta.onepub.dev');
      client.close(force: true);
      await server.close(force: true);
    });
    final paths = <String>[];
    server.listen((request) async {
      paths.add(request.uri.path);
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/api/provisioning/oauth/token') {
        await request.drain<void>();
        request.response.write(jsonEncode({
          'access_token': 'fixture-access',
          'refresh_token': 'next-refresh',
          'token_type': 'Bearer',
          'expires_in': 300,
          'scope': 'test:fixtures',
        }));
      } else {
        expect(request.uri.path, '/api/test/whoami');
        expect(request.headers.value(HttpHeaders.authorizationHeader),
            'Bearer fixture-access');
        request.response.write('{"body":{}}');
      }
      await request.response.close();
    });
    final result =
        await readiness.checkFixtureActivation(client, 'member-selector');
    expect(result.statusCode, 200);
    expect(paths, ['/api/provisioning/oauth/token', '/api/test/whoami']);
  });
  test('status checks reach the selected local server and preserve its port',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = HttpClient();
    selectPenTestTarget('http://127.0.0.1:${server.port}');
    addTearDown(() async {
      selectPenTestTarget('https://beta.onepub.dev');
      client.close(force: true);
      await server.close(force: true);
    });
    final served = server.first.then((request) async {
      expect(request.uri.path, '/api/status');
      request.response
        ..headers.contentType = ContentType.json
        ..write('{"body":{"version":"5.73.3"}}');
      await request.response.close();
    });
    final response = await readiness.check(client, '/api/status');
    expect(response.statusCode, 200);
    expect(readiness.versionFromStatus(response.body).toString(), '5.73.3');
    await served;
  });

  test('target preserves scheme and port for requests and credentials', () {
    final target = PenTestTarget('http://127.0.0.1:8080');
    expect(target.uri('/api/status').toString(),
        'http://127.0.0.1:8080/api/status');
    expect(target.owns(Uri.parse('http://127.0.0.1:8080/api/org')), isTrue);
    expect(target.owns(Uri.parse('http://127.0.0.1:8081/api/org')), isFalse);
    expect(target.owns(Uri.parse('https://127.0.0.1:8080/api/org')), isFalse);
    expect(target.owns(Uri.parse('https://beta.onepub.dev/api/org')), isFalse);
  });

  test('encoded probes retain their original path encoding', () {
    final target = PenTestTarget('https://test.example:8443');
    expect(target.encodedPath('/api/details%2Fextra').toString(),
        'https://test.example:8443/api/details%2Fextra');
    expect(target.uri('/search', {'query': 'a b'}).queryParameters,
        {'query': 'a b'});
  });

  test('rejects malformed origins and production targets', () {
    for (final value in [
      'file:///tmp/test',
      'https://user:secret@test.example',
      'https://test.example/api',
      'https://test.example?query=1',
      'https://test.example#fragment',
      'https://onepub.dev',
      'https://www.onepub.dev',
      'https://onepub.dev.',
      'https://WWW.ONEPUB.DEV.:8443',
    ]) {
      expect(() => PenTestTarget(value), throwsArgumentError);
    }
  });
}
