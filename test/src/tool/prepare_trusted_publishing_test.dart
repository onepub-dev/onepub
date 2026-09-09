import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../tool/prepare_trusted_publishing_test.dart';
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

  test('rejects verification when the second expected version is missing',
      () async {
    final server = await _startVerificationServer(
      publishedVersions: const ['1.0.0'],
    );
    addTearDown(() => server.close(force: true));

    final result =
        await _runVerification(server, expectedVersions: '1.0.0,1.0.1')
            .timeout(const Duration(seconds: 30));

    expect(result.exitCode, isNonZero,
        reason: '${result.stdout}\n${result.stderr}');
    expect(result.stderr, contains('Published versions do not match'));
  });

  test('rejects verification when the second archive cannot be downloaded',
      () async {
    final server = await _startVerificationServer(
      publishedVersions: const ['1.0.0', '1.0.1'],
      unavailableArchives: const {'1.0.1'},
    );
    addTearDown(() => server.close(force: true));

    final result =
        await _runVerification(server, expectedVersions: '1.0.0,1.0.1')
            .timeout(const Duration(seconds: 30));

    expect(result.exitCode, isNonZero,
        reason: '${result.stdout}\n${result.stderr}');
    expect(result.stderr, contains('Published archive download failed'));
  });

  test('verifies both published versions and archives', () async {
    final server = await _startVerificationServer(
      publishedVersions: const ['1.0.0', '1.0.1'],
    );
    addTearDown(() => server.close(force: true));

    final result =
        await _runVerification(server, expectedVersions: '1.0.0,1.0.1')
            .timeout(const Duration(seconds: 30));

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('Verified published package and archive'));
  });

  test('accepts a direct nonempty archive response', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    const token = 'direct-archive-secret';
    String? authorization;
    server.listen((request) async {
      authorization = request.headers.value('authorization');
      await _replyArchive(request, 'archive bytes');
    });

    await verifyPublishedArchive(_archiveUrl(server), token);

    expect(authorization, token);
  });

  test('follows a relative archive redirect without forwarding auth', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    const token = 'relative-archive-secret';
    final paths = <String>[];
    final authorizations = <String?>[];
    server.listen((request) async {
      paths.add(request.uri.path);
      authorizations.add(request.headers.value('authorization'));
      if (request.uri.path == '/archive') {
        await _replyArchive(request, '',
            status: HttpStatus.temporaryRedirect, location: 'grant');
      } else {
        await _replyArchive(request, 'archive bytes');
      }
    });

    await verifyPublishedArchive(_archiveUrl(server), token);

    expect(paths, ['/archive', '/grant']);
    expect(authorizations, [token, isNull]);
  });

  test('rejects a cross-origin archive redirect before contacting its grant',
      () async {
    final grantServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => grantServer.close(force: true));
    var grantRequests = 0;
    grantServer.listen((request) async {
      grantRequests++;
      await _replyArchive(request, 'must not download');
    });

    final archiveServer =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => archiveServer.close(force: true));
    const token = 'cross-origin-archive-secret';
    String? authorization;
    archiveServer.listen((request) async {
      authorization = request.headers.value('authorization');
      await _replyArchive(
        request,
        '',
        status: HttpStatus.temporaryRedirect,
        location: 'http://127.0.0.1:${grantServer.port}/grant',
      );
    });

    await expectLater(
      verifyPublishedArchive(_archiveUrl(archiveServer), token),
      throwsA(isA<StateError>().having(
        (error) => error.toString(),
        'error',
        allOf(
          contains('isolated test stack'),
          isNot(contains(token)),
        ),
      )),
    );

    expect(authorization, token);
    expect(grantRequests, 0);
  });

  test('rejects an archive after the redirect limit', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    const token = 'redirect-limit-secret';
    var requests = 0;
    final authorizations = <String?>[];
    server.listen((request) async {
      requests++;
      authorizations.add(request.headers.value('authorization'));
      await _replyArchive(request, '',
          status: HttpStatus.temporaryRedirect, location: '/archive');
    });

    await expectLater(
      verifyPublishedArchive(_archiveUrl(server), token),
      throwsA(isA<StateError>().having(
        (error) => error.message,
        'message',
        'Published archive exceeded the redirect limit.',
      )),
    );

    expect(requests, 6);
    expect(authorizations, [token, null, null, null, null, null]);
  });

  test('rejects an empty archive response', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      await _replyArchive(request, '');
    });

    await expectLater(
      verifyPublishedArchive(_archiveUrl(server), 'empty-archive-secret'),
      throwsA(isA<StateError>().having(
        (error) => error.message,
        'message',
        'Published archive is empty.',
      )),
    );
  });

  test('reports an archive HTTP status without exposing response content',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    const token = 'status-archive-secret';
    const responseSecret = 'response-secret-must-not-leak';
    server.listen((request) async {
      await _replyArchive(request, responseSecret,
          status: HttpStatus.serviceUnavailable);
    });

    await expectLater(
      verifyPublishedArchive(_archiveUrl(server), token),
      throwsA(isA<StateError>().having(
        (error) => error.toString(),
        'error',
        allOf(
          contains('HTTP 503'),
          isNot(contains(token)),
          isNot(contains(responseSecret)),
        ),
      )),
    );
  });

  test('rejects a redirect without a location', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      await _replyArchive(request, '', status: HttpStatus.temporaryRedirect);
    });

    await expectLater(
      verifyPublishedArchive(_archiveUrl(server), 'missing-location-secret'),
      throwsA(isA<StateError>().having(
        (error) => error.message,
        'message',
        'Published archive redirect has no location.',
      )),
    );
  });

  test('rejects a redirect containing user information', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      await _replyArchive(
        request,
        '',
        status: HttpStatus.temporaryRedirect,
        location: 'http://user:password@127.0.0.1:${server.port}/grant',
      );
    });

    await expectLater(
      verifyPublishedArchive(_archiveUrl(server), 'userinfo-secret'),
      throwsA(isA<StateError>().having(
        (error) => error.message,
        'message',
        'Archive redirect is not on the isolated test stack.',
      )),
    );
  });
}

const _verificationToken = 'verification-token';
const _verificationPackage = 'onepub_test_trusted_deadbeef';

Future<ProcessResult> _runVerification(
  HttpServer server, {
  required String expectedVersions,
}) {
  final script = p.join(
    Directory.current.path,
    'tool',
    'prepare_trusted_publishing_test.dart',
  );
  final url = assertSafeOnePubTestUrl(
    'http://127.0.0.1:${server.port}',
    source: 'trusted-publishing verification regression',
  );
  return Process.run(
    Platform.resolvedExecutable,
    [script, url, _verificationPackage, '--verify'],
    workingDirectory: Directory.current.path,
    environment: {
      ...Platform.environment,
      'ONEPUB_BOOTSTRAP_TEST_TOKEN': _verificationToken,
      'ONEPUB_E2E_EXPECTED_VERSIONS': expectedVersions,
    },
  );
}

Future<HttpServer> _startVerificationServer({
  required List<String> publishedVersions,
  Set<String> unavailableArchives = const <String>{},
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final versions = [
    for (final version in publishedVersions)
      {
        'version': version,
        'retracted': false,
        'archive_url': 'http://127.0.0.1:${server.port}/archive/$version',
        'pubspec': {
          'name': _verificationPackage,
          'version': version,
        },
      },
  ];

  server.listen((request) async {
    final authorization = request.headers.value('authorization');

    if (request.uri.path == '/api/organisation/details') {
      expect(request.method, 'GET');
      expect(authorization, _verificationToken);
      await _reply(request, {
        'body': {
          'organisationName': 'Trusted Publishing Test Org',
          'obfuscatedId': 'trusted-test-org',
        },
      });
      return;
    }

    if (request.uri.path ==
        '/api/trusted-test-org/api/packages/$_verificationPackage') {
      expect(request.method, 'GET');
      expect(authorization, _verificationToken);
      await _reply(request, {
        'name': _verificationPackage,
        'isDiscontinued': false,
        'replacedBy': '',
        'latest': versions.last,
        'versions': versions,
      });
      return;
    }

    if (request.uri.path.startsWith('/archive/')) {
      expect(request.method, 'GET');
      expect(authorization, _verificationToken);
      final version = request.uri.pathSegments.last;
      if (unavailableArchives.contains(version)) {
        await _reply(
            request,
            {
              'error': {'message': 'archive unavailable'},
            },
            status: HttpStatus.notFound);
      } else {
        await _replyArchive(request, '',
            status: HttpStatus.temporaryRedirect, location: '/grant/$version');
      }
      return;
    }

    if (request.uri.path.startsWith('/grant/')) {
      expect(request.method, 'GET');
      expect(authorization, isNull);
      await _replyArchive(request, 'archive bytes');
      return;
    }

    await _reply(
      request,
      {
        'error': {'message': 'Unexpected verification route'}
      },
      status: HttpStatus.notFound,
    );
  });
  return server;
}

Uri _archiveUrl(HttpServer server, [String path = '/archive']) => Uri.parse(
      assertSafeOnePubTestUrl(
        'http://127.0.0.1:${server.port}$path',
        source: 'trusted-publishing archive regression',
      ),
    );

Future<void> _replyArchive(
  HttpRequest request,
  String body, {
  int status = HttpStatus.ok,
  String? location,
}) async {
  request.response.statusCode = status;
  if (location != null) {
    request.response.headers.set(HttpHeaders.locationHeader, location);
  }
  request.response.add(utf8.encode(body));
  await request.response.close();
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
