import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../test_settings.dart';

void main() {
  late Directory fixture;
  late HttpServer server;
  late String target;
  late File operatorSettings;
  late File operatorTokens;
  final requests = <String>[];
  var administrator = true;

  setUp(() async {
    fixture = Directory.systemTemp.createTempSync('onepub-auth-hook-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    target = assertSafeOnePubTestUrl('http://127.0.0.1:${server.port}');
    administrator = true;
    requests.clear();
    server.listen((request) async {
      requests.add(request.uri.path);
      expect(request.headers.value('authorization'), 'fixture-token');
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'body': {
          'email': 'admin@example.test',
          'firstname': 'Test',
          'lastname': 'Admin',
          'roles': [if (administrator) 'SystemAdministrator'],
          'organisationName': 'Fixture',
          'obfuscateOrganisationId': 'fixture-org',
        },
      }));
      await request.response.close();
    });
    for (final path in [
      'tool/critical_test/pre_hook/auth.dart',
      'tool/check_system_test_prereqs.dart',
      'test/test_settings.dart',
    ]) {
      final destination = File(p.join(fixture.path, path));
      destination.parent.createSync(recursive: true);
      File(path).copySync(destination.path);
    }
    File(p.join(fixture.path, 'pubspec.yaml'))
        .writeAsStringSync('name: auth_hook_fixture\n');
    File(p.join(fixture.path, 'test/test_settings.yaml')).writeAsStringSync('''
onepubUrl: "$target"
organisationId: fixture-org
organisationName: Fixture
member: admin@example.test
onepub_token: fixture-token
''');
    operatorSettings = File(p.join(fixture.path, 'operator/onepub.yaml'));
    operatorSettings.parent.createSync();
    operatorSettings.writeAsStringSync('''
onepubUrl: https://onepub.dev
organisationId: production-org
''');
    operatorTokens =
        File(p.join(fixture.path, 'operator-tokens/pub-tokens.json'));
    operatorTokens.parent.createSync();
    operatorTokens.writeAsStringSync('{"version":1,"hosted":[]}');
  });

  tearDown(() async {
    await server.close(force: true);
    fixture.deleteSync(recursive: true);
  });

  Future<ProcessResult> runHook({String? override}) => Process.run(
        Platform.resolvedExecutable,
        [
          '--packages=${p.absolute('.dart_tool/package_config.json')}',
          p.join(fixture.path, 'tool/critical_test/pre_hook/auth.dart'),
        ],
        workingDirectory: fixture.path,
        environment: {
          'ONEPUB_PATH': operatorSettings.parent.path,
          '_PUB_TEST_CONFIG_DIR': operatorTokens.parent.path,
          'ONEPUB_STAGING_URL': override ?? target,
          'ONEPUB_TOKEN': 'unrelated-publishing-token',
        },
      );

  test('uses isolated test credentials despite production operator settings',
      () async {
    final originalSettings = operatorSettings.readAsStringSync();
    final originalTokens = operatorTokens.readAsStringSync();
    final result = await runHook();
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(requests, isNotEmpty);
    expect(
        requests
            .every((path) => path == '/api/test/member/details/fixture-token'),
        isTrue);
    expect(operatorSettings.readAsStringSync(), originalSettings);
    expect(operatorTokens.readAsStringSync(), originalTokens);
  });

  test('rejects production test target before any request', () async {
    final result = await runHook(override: 'https://onepub.dev');
    expect(result.exitCode, 2);
    expect(result.stderr, contains('must never run against production'));
    expect(requests, isEmpty);
  });

  test('still refuses a non-administrator test token', () async {
    administrator = false;
    final result = await runHook();
    expect(result.exitCode, 3);
    expect(result.stderr, contains('not a System Administrator'));
  });
}
