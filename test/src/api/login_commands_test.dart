import 'dart:convert';
import 'dart:io';

import 'package:onepub/src/exceptions.dart';
import 'package:onepub/src/my_runner.dart';
import 'package:onepub/src/onepub_settings.dart';
import 'package:onepub/src/util/login_persistence.dart';
import 'package:onepub/src/util/one_pub_token_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../test_settings.dart';

// Exercises actual command parsing, HTTP requests and disk persistence. The
// loopback responder is a contract fixture, not an IdP interoperability test.
void main() {
  late Directory temp;
  late HttpServer server;
  late String url;
  late List<Map<String, String>> routes;
  late bool supportsSso;
  late String method;
  late String status;
  late String code;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('onepub-login-commands-');
    addTearDown(() => temp.deleteSync(recursive: true));
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    url = assertSafeOnePubTestUrl('http://127.0.0.1:${server.port}',
        source: 'local login command contract tests');
    routes = [];
    supportsSso = true;
    method = 'sso';
    status = 'authSucceeded';
    code = 'acme';
    server.listen((request) async {
      Map<String, Object?> body;
      if (request.uri.path.endsWith('/status')) {
        body = {
          'message': 'Status normal',
          'version': '1.0.0',
          if (supportsSso) 'capabilities': ['enterprise-sso-v1'],
        };
      } else if (request.uri.path.contains('/member/awaitLogin/')) {
        routes.add(Map.of(request.uri.queryParameters));
        body = {
          'status': status,
          if (status == 'authSucceeded') ...{
            'onePubToken': 'fixture-token',
            'firstLogin': false,
            'operatorEmail': 'member@example.test',
            'organisationName': 'Acme',
            'obfuscatedOrganisationId': 'acme-id',
            if (supportsSso)
              'loginRouting': {
                'method': method,
                'organisationId': 'acme-id',
                if (method == 'sso') 'organisationCode': code,
              },
          },
        };
      } else if (request.uri.path.endsWith('/member/logout')) {
        body = {'message': 'Logged out'};
      } else {
        request.response.statusCode = HttpStatus.notFound;
        body = {};
      }
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'body': body}));
      await request.response.close();
    });
  });

  Future<void> scoped(Future<void> Function() action) =>
      OnePubSettings.withPathTo(p.join(temp.path, 'settings'), () async {
        final settings = OnePubSettings.use()..onepubUrl = url;
        await settings.save();
        await OnePubTokenStore.withPathTo(p.join(temp.path, 'tokens'), action);
      });

  Future<int?> run(List<String> args) {
    final runner = MyRunner(args, 'onepub', 'test');
    return runner.run(runner.args);
  }

  test('commands remember login, allow choosing and distinguish logout/forget',
      () async {
    await scoped(() async {
      final persistence = LoginPersistence(OnePubSettings.use());
      await run(['login']);
      expect(routes.last, {'routingMode': 'choose'});
      expect((await persistence.preferences.load(persistence.server))?.method,
          'sso');

      await run(['login']);
      expect(routes.last, {
        'routingMode': 'hint',
        'loginMethod': 'sso',
        'organisationCode': 'acme',
        'organisationId': 'acme-id',
      });
      await run(['logout']);
      expect(
          await OnePubTokenStore()
              .isLoggedIn(OnePubSettings.use().onepubApiUrl),
          isFalse);
      expect(await persistence.preferences.load(persistence.server), isNotNull);

      await run(['login', 'sso', 'ACME']);
      expect(routes.last, {
        'routingMode': 'fixed',
        'loginMethod': 'sso',
        'organisationCode': 'acme',
      });
      method = 'ordinary';
      await run(['login', '--choose']);
      expect(routes.last, {'routingMode': 'choose'});
      expect((await persistence.preferences.load(persistence.server))?.method,
          'ordinary');
      await run(['login', 'browser']);
      expect(routes.last, {'routingMode': 'fixed', 'loginMethod': 'ordinary'});
      await run(['logout', '--forget']);
      expect(await persistence.preferences.load(persistence.server), isNull);
      await run(['login']);
      expect(routes.last, {'routingMode': 'choose'});
    });
  });

  test('failed or mismatched SSO leaves the previous login intact', () async {
    await scoped(() async {
      await run(['login', 'sso', 'acme']);
      final settings = OnePubSettings.use();
      final persistence = LoginPersistence(settings);
      final before = File(settings.pathToSettings).readAsStringSync();
      final preference = persistence.preferences.file.readAsStringSync();
      for (final failure in ['authFailed', 'timeout', 'wrong organisation']) {
        status = failure == 'wrong organisation' ? 'authSucceeded' : failure;
        code = failure == 'wrong organisation' ? 'another' : 'acme';
        await expectLater(
            run(['login', 'sso', 'acme']), throwsA(isA<ExitException>()));
        expect(File(settings.pathToSettings).readAsStringSync(), before);
        expect(persistence.preferences.file.readAsStringSync(), preference);
        expect(await OnePubTokenStore().load(), 'fixture-token');
      }
    });
  });

  test('old server rejects explicit SSO but ordinary browser login still works',
      () async {
    await scoped(() async {
      supportsSso = false;
      await expectLater(
          run(['login', 'sso', 'acme']), throwsA(isA<ExitException>()));
      expect(routes, isEmpty);
      await run(['login', 'browser']);
      expect(routes.single, isEmpty);
      expect(await OnePubTokenStore().load(), 'fixture-token');
      final persistence = LoginPersistence(OnePubSettings.use());
      expect((await persistence.preferences.load(persistence.server))?.method,
          'ordinary');
    });
  });
}
