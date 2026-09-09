import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:onepub/src/api/api.dart';
import 'package:onepub/src/commands/import.dart';
import 'package:onepub/src/exceptions.dart';
import 'package:onepub/src/onepub_settings.dart';
import 'package:onepub/src/util/one_pub_token_store.dart';
import 'package:onepub/src/util/send_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../test_settings.dart';

void main() {
  late HttpServer server;
  late Directory temp;
  late String url;
  late List<String> requests;
  late Future<void> Function(HttpRequest) handler;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('onepub-audit-');
    addTearDown(() => temp.deleteSync(recursive: true));
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    url = assertSafeOnePubTestUrl('http://127.0.0.1:${server.port}',
        source: 'local import audit tests');
    requests = [];
    server.listen((request) async {
      requests.add(request.uri.path);
      await handler(request);
    });
  });

  Future<void> scoped(Future<void> Function() action) =>
      OnePubSettings.withPathTo(p.join(temp.path, 'settings'), () async {
        final settings = OnePubSettings.use()
          ..onepubUrl = url
          ..organisationName = 'Original Org'
          ..obfuscatedOrganisationId = 'test-org';
        await settings.save();
        await OnePubTokenStore.withPathTo(p.join(temp.path, 'tokens'), action);
      });

  Future<void> reply(HttpRequest request, Object body,
      {int status = 200}) async {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await request.response.close();
  }

  Future<void> importToken() async {
    final file = File(p.join(temp.path, 'import.yaml'))
      ..writeAsStringSync('onepubToken: imported-token\n');
    final runner = CommandRunner<int>('onepub', 'test')
      ..addCommand(ImportCommand());
    expect(await runner.run(['import', '--file', file.path]), 0);
  }

  for (final scenario in [
    'success',
    '500',
    'malformed',
    'stalled headers',
    'stalled body'
  ]) {
    test('import saves credentials when audit returns $scenario', () async {
      Map<String, dynamic>? audit;
      String? authorization;
      String? initiator;
      handler = (request) async {
        if (request.uri.path.endsWith('/status')) {
          await reply(request, {
            'body': {
              'message': 'Status normal',
              'version': '5.15.18',
            }
          });
        } else if (request.uri.path.endsWith('/organisation/details')) {
          await reply(request, {
            'body': {
              'organisationName': 'Imported Org',
              'obfuscatedId': 'test-org',
            }
          });
        } else {
          expect(request.uri.path, '/api/member/importToken');
          expect(request.method, 'POST');
          expect(request.headers.contentType?.mimeType, 'application/json');
          authorization = request.headers.value('authorization');
          initiator = request.headers.value('x-onepub-initiator-token');
          audit = jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>;
          switch (scenario) {
            case 'success':
              await reply(request, {
                'success': {'message': 'Logged'}
              });
            case '500':
              await reply(
                  request,
                  {
                    'error': {'message': 'Unavailable'}
                  },
                  status: 500);
            case 'malformed':
              request.response.write('not JSON');
              await request.response.close();
            case 'stalled headers':
              return;
            case 'stalled body':
              request.response.write('{');
              await request.response.flush();
          }
        }
      };
      await scoped(() async {
        await OnePubTokenStore().addToken(
          onepubApiUrl: OnePubSettings.use().onepubApiUrlAsString,
          onepubToken: 'original-token',
        );
        await importToken().timeout(const Duration(seconds: 9));
        expect(await OnePubTokenStore().load(), 'imported-token');
        expect(OnePubSettings.use().organisationName, 'Imported Org');
        expect(File(OnePubSettings.use().pathToSettings).readAsStringSync(),
            contains('Imported Org'));
        expect(authorization, 'imported-token');
        expect(initiator, 'original-token');
        expect(audit!['tokenSource'], 'file');
        expect(audit!['os'], Platform.operatingSystem);
        expect(
            audit!.keys,
            unorderedEquals([
              'tokenSource',
              'ci',
              'ciProvider',
              'host',
              'user',
              'os',
              'shell'
            ]));
      });
    });
  }

  for (final endpoint in ['status', 'organisation/details']) {
    test('invalid $endpoint leaves stored settings and token unchanged',
        () async {
      handler = (request) async {
        if (request.uri.path.endsWith('/status') && endpoint != 'status') {
          await reply(request, {
            'body': {
              'message': 'Status normal',
              'version': '5.15.18',
            }
          });
        } else {
          await reply(request, {'body': <String, dynamic>{}});
        }
      };
      await scoped(() async {
        final settings = OnePubSettings.use();
        await OnePubTokenStore().addToken(
            onepubApiUrl: settings.onepubApiUrlAsString,
            onepubToken: 'original-token');
        final before = File(settings.pathToSettings).readAsStringSync();
        await expectLater(importToken(), throwsA(isA<APIException>()));
        expect(File(settings.pathToSettings).readAsStringSync(), before);
        expect(await OnePubTokenStore().load(), 'original-token');
        expect(requests, isNot(contains('/api/member/importToken')));
      });
    });
  }

  test('request deadline closes an in-flight HTTP connection', () async {
    final disconnected = Completer<void>();
    handler = (request) async {
      final socket = await request.response.detachSocket(writeHeaders: false);
      socket.listen((_) {}, onDone: () {
        disconnected.complete();
        socket.destroy();
      });
    };
    await scoped(() async {
      await expectLater(
          sendCommand(
              command: '/status',
              commandType: CommandType.cli,
              authorised: false,
              timeout: const Duration(milliseconds: 100)),
          throwsA(isA<TimeoutException>()));
      await disconnected.future.timeout(const Duration(seconds: 2));
    });
  });

  test('UTF-8 characters split between packets decode correctly', () async {
    handler = (request) async {
      final bytes =
          utf8.encode('{"body":{"message":"Café","version":"5.15.18"}}');
      final split = bytes.indexOf(0xc3) + 1;
      request.response.add(bytes.sublist(0, split));
      await request.response.flush();
      request.response.add(bytes.sublist(split));
      await request.response.close();
    };
    await scoped(() async {
      expect((await API().status()).message, 'Café');
    });
  });
}
