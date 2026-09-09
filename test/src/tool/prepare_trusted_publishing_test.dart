import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../test_settings.dart';

void main() {
  test('creates the trusted-publishing package with POST', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    final url = assertSafeOnePubTestUrl(
      'http://127.0.0.1:${server.port}',
      source: 'trusted-publishing bootstrap regression',
    );
    const token = 'bootstrap-token';
    const packageName = 'onepub_test_trusted_deadbeef';
    final requests = <String>[];

    server.listen((request) async {
      requests.add('${request.method} ${request.uri.path}');
      final authorization = request.headers.value('authorization');

      if (request.uri.path == '/api/organisation/details') {
        expect(request.method, 'GET');
        expect(authorization, token);
        await _reply(request, {
          'body': {
            'organisationName': 'Trusted Publishing Test Org',
            'obfuscatedId': 'trusted-test-org',
          },
        });
        return;
      }

      if (request.uri.path == '/api/test/team/list') {
        expect(request.method, 'GET');
        expect(authorization, token);
        await _reply(request, {
          'body': {
            'teams': [
              {
                'id': 1,
                'name': 'Everyone Team',
                'everyoneTeam': true,
                'leader': true,
              },
            ],
          },
        });
        return;
      }

      if (request.uri.path == '/api/test/package/create/$packageName') {
        expect(authorization, token);
        expect(request.uri.queryParameters['team'], 'Everyone Team');
        if (request.method == 'GET') {
          await _reply(
            request,
            {
              'error': {'message': 'Package create requires POST'}
            },
            status: HttpStatus.notFound,
          );
        } else {
          expect(request.method, 'POST');
          await _reply(request, {
            'success': {'message': 'Package created'},
          });
        }
        return;
      }

      await _reply(
        request,
        {
          'error': {'message': 'Unexpected bootstrap route'}
        },
        status: HttpStatus.notFound,
      );
    });

    final script = p.join(
      Directory.current.path,
      'tool',
      'prepare_trusted_publishing_test.dart',
    );
    final result = await Process.run(
      Platform.resolvedExecutable,
      [script, url, packageName],
      workingDirectory: Directory.current.path,
      environment: {
        ...Platform.environment,
        'ONEPUB_BOOTSTRAP_TEST_TOKEN': token,
      },
    ).timeout(const Duration(seconds: 30));

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(
      requests,
      containsAllInOrder([
        'GET /api/organisation/details',
        'GET /api/test/team/list',
        'POST /api/test/package/create/$packageName',
      ]),
    );
    expect(
      requests.where(
          (request) => request.startsWith('GET /api/test/package/create/')),
      isEmpty,
    );
  });
}

Future<void> _reply(
  HttpRequest request,
  Object body, {
  int status = 200,
}) async {
  request.response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
  await request.response.close();
}
