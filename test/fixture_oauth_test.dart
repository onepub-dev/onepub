import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dcli/posix.dart' show chmod;
import 'package:dcli_core/dcli_core.dart' as core;
import 'package:onepub/src/onepub_settings.dart';
import 'package:onepub/src/util/send_command.dart';
import 'package:test/test.dart';

import 'fixture_oauth.dart';
import 'scim_test_client.dart';
import 'test_settings.dart';

void main() {
  tearDown(FixtureOAuth.reset);

  test('nested login install retains private target and helper pins origin',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var helperRequests = 0;
    final refreshes = <String>[];
    server.listen((request) async {
      if (request.uri.path == '/api/provisioning/oauth/token') {
        final form = Uri.splitQueryString(
          await utf8.decoder.bind(request).join(),
        );
        refreshes.add(form['refresh_token']!);
        await _replyToken(
          request,
          '${form['refresh_token']}-access',
          '${form['refresh_token']}-next',
        );
      } else {
        helperRequests++;
        expect(request.uri.path, '/api/test/auth/completeCliLogin/pending');
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer root-refresh-access',
        );
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'success': true,
            'body': {
              'onepubToken': 'child-member',
              'testFixtureRefreshToken': 'child-refresh',
              'testFixtureScopes': 'test:fixtures',
            },
          }),
        );
        await request.response.close();
      }
    });
    final url = _origin(server);
    FixtureOAuth.configure(url, {..._seed, 'onepubUrl': url});
    await core.withTempDirAsync((directory) async {
      final defaultHome = Directory('$directory/clean-home')..createSync();
      final privateSettings = '$directory/login-settings';
      await core.withEnvironmentAsync(
        () async {
          await OnePubSettings.withPathTo(privateSettings, () async {
            final settings = OnePubSettings.use()..onepubUrl = url;
            await settings.save();
            await core.withEnvironmentAsync(() async {
              await OnePubSettings.install(dev: false);
              expect(OnePubSettings.use().onepubUrl, url);
              expect(
                File('${defaultHome.path}/.onepub/onepub.yaml').existsSync(),
                isFalse,
              );
              // The login helper must remain pinned even if nested code changes
              // the ambient configuration before its pending-login callback.
              settings.onepubUrl = OnePubSettings.defaultOnePubUrl;
              final response = await sendFixtureCommand(
                command: 'test/auth/completeCliLogin/pending',
                commandType: CommandType.cli,
                actor: 'root-member',
                onepubUrl: url,
                method: Method.post,
              );
              expect(response.status, HttpStatus.ok);
              expect(
                await FixtureOAuth.token(actor: 'child-member', onepubUrl: url),
                'child-refresh-access',
              );
              await expectLater(
                FixtureOAuth.accept({
                  'onepubToken': 'foreign-child',
                  'testFixtureRefreshToken': 'foreign-refresh',
                  'testFixtureScopes': 'test:fixtures',
                }, onepubUrl: 'http://127.0.0.1:${server.port + 1}'),
                throwsA(isA<ScimTestException>()),
              );
              await expectLater(
                FixtureOAuth.token(actor: 'foreign-child', onepubUrl: url),
                throwsA(isA<ScimTestException>()),
              );
              await expectLater(
                sendFixtureCommand(
                  command: 'test/auth/completeCliLogin/pending',
                  commandType: CommandType.cli,
                  actor: 'root-member',
                  onepubUrl: OnePubSettings.defaultOnePubUrl,
                ),
                throwsStateError,
              );
              await expectLater(
                sendFixtureCommand(
                  command: 'test/auth/completeCliLogin/pending',
                  commandType: CommandType.cli,
                  actor: 'root-member',
                  onepubUrl: 'http://127.0.0.1:${server.port + 1}',
                ),
                throwsA(isA<ScimTestException>()),
              );
            }, environment: {'ONEPUB_PATH': privateSettings});
            expect(core.env['ONEPUB_PATH'], '${defaultHome.path}/.onepub');
          });
        },
        environment: {
          'HOME': defaultHome.path,
          'ONEPUB_PATH': '${defaultHome.path}/.onepub',
        },
      );
    });
    expect(helperRequests, 1);
    expect(refreshes, ['root-refresh', 'child-refresh']);
  });

  test(
    'detached broker private handoff closes when parent pipe exits',
    () async {
      final server = await _tokenServer();
      addTearDown(() => server.close(force: true));
      final state = await Directory.systemTemp.createTemp(
        'fixture-broker-state-',
      );
      addTearDown(() => state.delete(recursive: true));
      chmod(state.path, permission: '700');
      final url = _origin(server);
      final process = await Process.start(
        File('tool/critical_test/fixture_broker.dart').absolute.path,
        [state.path],
        environment: {
          FixtureOAuth.authorizationKey: jsonEncode({
            ..._seed,
            'onepubUrl': url,
          }),
        },
      );
      addTearDown(process.kill);
      final output = process.stdout.transform(utf8.decoder).join();
      final errors = process.stderr.transform(utf8.decoder).join();
      final file = File('${state.path}/broker.json');
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (!file.existsSync()) {
        if (DateTime.now().isAfter(deadline)) {
          fail('Detached broker did not publish its private handoff.');
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      final encoded = await FixtureOAuth.readCriticalBroker(state, url);
      expect(file.readAsStringSync(), isNot(contains('root-refresh')));
      final broker = jsonDecode(encoded!) as Map<String, dynamic>;
      final response = await _brokerRequest(
        broker['url'] as String,
        broker['secret'] as String,
        {
          'operation': 'token',
          'origin': url,
          'actor': 'root-member',
          'root': false,
        },
      );
      expect(response.$1, HttpStatus.ok);
      await expectLater(
        FixtureOAuth.readCriticalBroker(state, '$url/other'),
        throwsA(isA<ScimTestException>()),
      );
      chmod(file.path, permission: '644');
      await expectLater(
        FixtureOAuth.readCriticalBroker(state, url),
        throwsA(isA<ScimTestException>()),
      );
      chmod(file.path, permission: '600');
      final link = Link('${state.path}-link')..createSync(state.path);
      addTearDown(link.delete);
      await expectLater(
        FixtureOAuth.readCriticalBroker(Directory(link.path), url),
        throwsA(isA<ScimTestException>()),
      );
      await process.stdin.close();
      expect(await process.exitCode.timeout(const Duration(seconds: 10)), 0);
      expect(file.existsSync(), isFalse);
      expect('${await output}${await errors}', isNot(contains('root-refresh')));
      await expectLater(
        _brokerRequest(broker['url'] as String, broker['secret'] as String, {}),
        throwsA(isA<SocketException>()),
      );
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );

  test(
    'parent harness preserves reporter arguments and child exit status',
    () async {
      final environment = <String, String>{
        FixtureOAuth.authorizationKey: jsonEncode({
          ..._seed,
          'onepubUrl': 'http://127.0.0.1:1',
        }),
      };
      final result = await Process.run(
          'tool/run_fixture_oauth_tests.dart',
          [
            '--reporter=json',
            '--plain-name=rejects production onepub',
            'test/test_settings_test.dart',
          ],
          environment: environment);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final events = (result.stdout as String)
          .split('\n')
          .where((line) => line.isNotEmpty)
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .toList();
      expect(
        events.where((event) => event['type'] == 'done').single['success'],
        isTrue,
      );
      expect(
        events.where((event) => event['type'] == 'testStart'),
        hasLength(2),
      );
      final failed = await Process.run(
          'tool/run_fixture_oauth_tests.dart',
          [
            '--reporter=json',
            'test/nonexistent_fixture_oauth_test.dart',
          ],
          environment: environment);
      expect(failed.exitCode, isNonZero);
      expect(
        '${result.stdout}${result.stderr}${failed.stdout}${failed.stderr}',
        isNot(contains('root-refresh')),
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'unknown actor and customer SCIM scope fail without member fallback',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var requests = 0;
      server.listen((request) async {
        requests++;
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
      });
      final url = _origin(server);
      expect(
        () => FixtureOAuth.configure(url, {
          ..._seed,
          'onepubUrl': url,
          'scopes': 'scim',
        }),
        throwsA(isA<ScimTestException>()),
      );
      expect(
        () => FixtureOAuth.configure(url, _seed),
        throwsA(isA<ScimTestException>()),
      );
      expect(
        () => FixtureOAuth.configure(url, {
          ..._seed,
          'onepubUrl': 'http://127.0.0.1:${server.port + 1}',
        }),
        throwsA(isA<ScimTestException>()),
      );
      FixtureOAuth.configure(url, {..._seed, 'onepubUrl': url});
      await _settings(url, () async {
        await expectLater(
          FixtureOAuth.token(actor: 'unknown-member-token'),
          throwsA(isA<ScimTestException>()),
        );
        await expectLater(
          sendFixtureCommand(
            command: 'test/whoami',
            commandType: CommandType.cli,
            actor: 'unknown-member-token',
          ),
          throwsA(isA<ScimTestException>()),
        );
        await expectLater(
          sendFixtureCommand(
            command: 'test/member/exportToken/other-org/target%40example.test',
            commandType: CommandType.cli,
            actor: 'unknown-member-token',
          ),
          throwsA(isA<ScimTestException>()),
        );
      });
      expect(requests, 0);
    },
  );

  test('child registration is exact actor and origin scoped', () async {
    var exchanges = 0;
    final server = await _tokenServer(onExchange: () => exchanges++);
    addTearDown(() => server.close(force: true));
    final url = _origin(server);
    FixtureOAuth.configure(url, {..._seed, 'onepubUrl': url});
    await _settings(url, () async {
      await expectLater(
        FixtureOAuth.accept({
          'onepubToken': 'customer-member',
          'testFixtureRefreshToken': 'customer-refresh',
          'testFixtureScopes': 'scim',
        }),
        throwsA(isA<ScimTestException>()),
      );
      await FixtureOAuth.accept({
        'onepubToken': 'child-member',
        'testFixtureRefreshToken': 'child-refresh',
        'testFixtureScopes': 'test:fixtures',
      });
      expect(
        await FixtureOAuth.token(actor: 'child-member'),
        'child-refresh-access',
      );
      await FixtureOAuth.accept({
        'onepubToken': 'child-member',
        'testFixtureRefreshToken': 'child-refresh',
        'testFixtureScopes': 'test:fixtures',
      });
      expect(
        await FixtureOAuth.token(actor: 'child-member'),
        'child-refresh-access',
      );
      await expectLater(
        FixtureOAuth.token(actor: 'other-member'),
        throwsA(isA<ScimTestException>()),
      );
      await FixtureOAuth.accept({
        'onepubToken': 'root-member',
        'testFixtureRefreshToken': 'attenuated-root-child',
        'testFixtureScopes': 'test:fixtures',
      });
      expect(await FixtureOAuth.token(root: true), 'root-refresh-access');
    });
    expect(exchanges, 2);
    await _settings('http://127.0.0.1:${server.port + 1}', () async {
      await expectLater(
        FixtureOAuth.token(actor: 'child-member'),
        throwsA(isA<ScimTestException>()),
      );
    });
  });

  test('fixture denial never retries with the member credential', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final helperCredentials = <String?>[];
    server.listen((request) async {
      if (request.uri.path == '/api/provisioning/oauth/token') {
        await utf8.decoder.bind(request).join();
        await _replyToken(request, 'fixture-access', 'fixture-next');
      } else {
        expect(request.uri.path, '/api/test/whoami');
        helperCredentials.add(
          request.headers.value(HttpHeaders.authorizationHeader),
        );
        request.response
          ..statusCode = HttpStatus.forbidden
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'error': {'message': 'Test resource access denied'},
            }),
          );
        await request.response.close();
      }
    });
    final url = _origin(server);
    FixtureOAuth.configure(url, {..._seed, 'onepubUrl': url});
    await _settings(url, () async {
      final result = await sendFixtureCommand(
        command: 'test/whoami',
        commandType: CommandType.cli,
        actor: 'root-member',
      );
      expect(result.success, isFalse);
    });
    expect(helperCredentials, ['Bearer fixture-access']);
  });

  test(
    'concurrent grant consumers serialize refresh and share access token',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final exchangeStarted = Completer<void>();
      final releaseExchange = Completer<void>();
      var exchanges = 0;
      server.listen((request) async {
        exchanges++;
        final form = Uri.splitQueryString(
          await utf8.decoder.bind(request).join(),
        );
        expect(form['grant_type'], 'refresh_token');
        expect(form['refresh_token'], 'root-refresh');
        exchangeStarted.complete();
        await releaseExchange.future;
        await _replyToken(request, 'shared-access', 'rotated-refresh');
      });
      final url = _origin(server);
      FixtureOAuth.configure(url, {..._seed, 'onepubUrl': url});
      await _settings(url, () async {
        final requests = List.generate(
          12,
          (_) => FixtureOAuth.token(actor: 'root-member'),
        );
        await exchangeStarted.future;
        releaseExchange.complete();
        expect(await Future.wait(requests), everyElement('shared-access'));
      });
      expect(exchanges, 1);
    },
  );

  test(
    'helper redirect cannot forward fixture credentials to another origin',
    () async {
      final destination = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => destination.close(force: true));
      var destinationRequests = 0;
      destination.listen((request) async {
        destinationRequests++;
        await request.response.close();
      });
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        if (request.uri.path == '/api/provisioning/oauth/token') {
          await utf8.decoder.bind(request).join();
          await _replyToken(request, 'fixture-access', 'fixture-next');
        } else {
          expect(
            request.headers.value(HttpHeaders.authorizationHeader),
            'Bearer fixture-access',
          );
          request.response.statusCode = HttpStatus.temporaryRedirect;
          request.response.headers.set(
            HttpHeaders.locationHeader,
            '${_origin(destination)}/capture',
          );
          await request.response.close();
        }
      });
      final url = _origin(server);
      FixtureOAuth.configure(url, {..._seed, 'onepubUrl': url});
      await _settings(url, () async {
        await expectLater(
          sendFixtureCommand(
            command: 'test/whoami',
            commandType: CommandType.cli,
            actor: 'root-member',
          ),
          throwsA(isA<ScimTestException>()),
        );
      });
      expect(destinationRequests, 0);
    },
  );

  test(
    'broker shares one grant across isolates and strips rotating seed',
    () async {
      var exchanges = 0;
      final server = await _tokenServer(onExchange: () => exchanges++);
      addTearDown(() => server.close(force: true));
      final url = _origin(server);
      final broker = await FixtureOAuth.startHarness(
        url,
        authorization: {..._seed, 'onepubUrl': url},
      );
      addTearDown(broker.close);
      final environment = broker.workerEnvironment({
        FixtureOAuth.authorizationKey: jsonEncode(_seed),
        'UNCHANGED': 'value',
      });
      expect(environment.containsKey(FixtureOAuth.authorizationKey), isFalse);
      expect(environment['UNCHANGED'], 'value');
      expect(environment.toString(), isNot(contains('root-refresh')));
      expect(environment.toString(), isNot(contains('client-secret')));
      final config = jsonDecode(
        environment[FixtureOAuth.brokerKey]!,
      ) as Map<String, dynamic>;
      final endpoint = config['url'] as String;
      final secret = config['secret'] as String;
      final results = await Future.wait(
        List.generate(6, (_) => _isolatedBrokerRequest(endpoint, secret, url)),
      );
      expect(
        results,
        everyElement((HttpStatus.ok, '{"accessToken":"root-refresh-access"}')),
      );
      expect(exchanges, 1);
    },
  );

  test(
    'concurrent explicit rotations consume each refresh token only once',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final presented = <String>[];
      server.listen((request) async {
        final form = Uri.splitQueryString(
          await utf8.decoder.bind(request).join(),
        );
        presented.add(form['refresh_token']!);
        await _replyToken(
          request,
          'access-${presented.length}',
          'refresh-${presented.length}',
        );
      });
      final client = ScimTestClient.refreshToken(
        onepubUrl: _origin(server),
        clientId: 'fixture-client',
        clientSecret: 'client-secret',
        refreshToken: 'root-refresh',
      );
      await Future.wait(List.generate(3, (_) => client.refresh()));
      expect(presented, [
        'root-refresh',
        'refresh-1',
        'refresh-2',
        'refresh-3',
      ]);
      expect(await client.accessToken(), 'access-4');
    },
  );

  test(
    'broker rejects unauthenticated, foreign, oversized and unknown requests',
    () async {
      var exchanges = 0;
      final server = await _tokenServer(onExchange: () => exchanges++);
      addTearDown(() => server.close(force: true));
      final url = _origin(server);
      final broker = await FixtureOAuth.startHarness(
        url,
        authorization: {..._seed, 'onepubUrl': url},
      );
      final config = jsonDecode(
        broker.workerEnvironment({})[FixtureOAuth.brokerKey]!,
      ) as Map<String, dynamic>;
      final endpoint = config['url'] as String;
      final secret = config['secret'] as String;
      final body = {
        'operation': 'token',
        'origin': url,
        'actor': 'root-member',
        'root': false,
      };
      try {
        for (final entry in [
          (endpoint, 'wrong-secret', body),
          ('$endpoint?unexpected=true', secret, body),
          (
            endpoint,
            secret,
            {...body, 'origin': 'http://127.0.0.1:${server.port + 1}'},
          ),
          (endpoint, secret, {...body, 'actor': 'unknown'}),
          (endpoint, secret, {...body, 'operation': 'arbitrary'}),
          (endpoint, secret, {...body, 'padding': 'x' * 65537}),
        ]) {
          final response = await _brokerRequest(entry.$1, entry.$2, entry.$3);
          expect(response.$1, HttpStatus.forbidden);
          expect(response.$2, isNot(contains(secret)));
          expect(response.$2, isNot(contains('root-refresh')));
        }
        expect(exchanges, 0);
      } finally {
        await broker.close();
      }
      await expectLater(
        _brokerRequest(endpoint, secret, body),
        throwsA(isA<SocketException>()),
      );
    },
  );
}

const _seed = <String, dynamic>{
  'clientId': 'fixture-client',
  'clientSecret': 'client-secret',
  'refreshToken': 'root-refresh',
  'onepubToken': 'root-member',
  'scopes': 'test:fixtures',
};

String _origin(HttpServer server) => assertSafeOnePubTestUrl(
      'http://127.0.0.1:${server.port}',
      source: 'fixture OAuth regression',
    );

Future<void> _settings(String url, Future<void> Function() action) =>
    core.withTempDirAsync(
      (directory) => OnePubSettings.withPathTo(directory, () async {
        OnePubSettings.use().onepubUrl = url;
        await action();
      }),
    );

Future<HttpServer> _tokenServer({void Function()? onExchange}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    onExchange?.call();
    expect(request.uri.path, '/api/provisioning/oauth/token');
    expect(
      request.headers.value(HttpHeaders.authorizationHeader),
      'Basic ${base64Encode(utf8.encode('fixture-client:client-secret'))}',
    );
    final form = Uri.splitQueryString(await utf8.decoder.bind(request).join());
    expect(form['grant_type'], 'refresh_token');
    final refresh = form['refresh_token']!;
    await _replyToken(request, '$refresh-access', '$refresh-next');
  });
  return server;
}

Future<void> _replyToken(
  HttpRequest request,
  String access,
  String refresh,
) async {
  request.response.headers.contentType = ContentType.json;
  request.response.write(
    jsonEncode({
      'access_token': access,
      'refresh_token': refresh,
      'token_type': 'Bearer',
      'expires_in': 300,
      'scope': 'test:fixtures',
    }),
  );
  await request.response.close();
}

Future<(int, String)> _brokerRequest(
  String endpoint,
  String secret,
  Map<String, dynamic> body,
) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final request = await client.postUrl(Uri.parse(endpoint));
    request.followRedirects = false;
    request.headers.set(HttpHeaders.authorizationHeader, secret);
    request.write(jsonEncode(body));
    final response = await request.close();
    return (response.statusCode, await utf8.decoder.bind(response).join());
  } finally {
    client.close(force: true);
  }
}

// Only serializable request values enter the worker closure; no server or grant
// owner object is captured or shared with an isolate.
Future<(int, String)> _isolatedBrokerRequest(
  String endpoint,
  String secret,
  String origin,
) =>
    Isolate.run(
      () => _brokerRequest(endpoint, secret, {
        'operation': 'token',
        'origin': origin,
        'actor': 'root-member',
        'root': false,
      }),
    );
