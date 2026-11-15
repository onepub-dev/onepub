import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:onepub/src/onepub_settings.dart';
import 'package:onepub/src/util/login_persistence.dart';
import 'package:onepub/src/util/one_pub_token_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../test_settings.dart';

// The candidate server drives only the printed challenge URLs through Selenium.
// Each command is the shipped entry point in a new OS process, not MyRunner.
void main() {
  if (Platform.environment['ONEPUB_SAML_E2E_FAILURE'] != null) {
    _failureLane();
    return;
  }
  test('real CLI processes complete browser SAML and reuse stored credentials',
      () async {
    final environment = Platform.environment;
    final server = Uri.parse(assertSafeOnePubTestUrl(
        environment['ONEPUB_SAML_E2E_URL']!,
        source: 'candidate SAML browser lane'));
    expect(server.scheme, 'http');
    expect(['127.0.0.1', 'localhost', '::1'], contains(server.host));
    final code = environment['ONEPUB_SAML_E2E_CODE']!;
    final organisationId = environment['ONEPUB_SAML_E2E_ORGANISATION']!;
    final otherOrganisation =
        environment['ONEPUB_SAML_E2E_OTHER_ORGANISATION']!;
    final otherCode = environment['ONEPUB_SAML_E2E_OTHER_CODE']!;
    final email = environment['ONEPUB_SAML_E2E_EMAIL']!;
    final directory = Directory.systemTemp.createTempSync('onepub-saml-e2e-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final settingsPath = p.join(directory.path, 'settings');
    final tokensPath = p.join(directory.path, 'tokens');
    final commandEnvironment = Map<String, String>.of(environment)
      ..removeWhere((key, _) =>
          key.startsWith('ONEPUB_') || key == '_PUB_TEST_CONFIG_DIR')
      ..['ONEPUB_PATH'] = settingsPath
      ..['_PUB_TEST_CONFIG_DIR'] = tokensPath;
    await OnePubSettings.withPathTo(settingsPath, () async {
      final settings = OnePubSettings.use()..onepubUrl = server.toString();
      await settings.save();
      await OnePubTokenStore.withPathTo(tokensPath, () async {
        expect(await OnePubTokenStore().isLoggedIn(settings.onepubApiUrl),
            isFalse);
        final commands = <String, List<String>>{
          'first': ['login'],
          'explicit': ['login', 'sso', code],
          'remembered': ['login'],
          'retry': ['login', 'sso', code],
          'choose': ['login', '--choose'],
        };
        for (final stage in commands.entries) {
          final expectedOrganisation =
              stage.key == 'choose' ? otherOrganisation : organisationId;
          final foreignOrganisation =
              stage.key == 'choose' ? organisationId : otherOrganisation;
          print('SSO_BROWSER_STAGE:${stage.key}');
          await _command(stage.value, commandEnvironment, server,
              forwardChallenge: true);
          settings.reload();
          final persistence = LoginPersistence(settings);
          final routing =
              await persistence.preferences.load(persistence.server);
          expect(routing?.method, 'sso');
          expect(routing?.organisationCode,
              stage.key == 'choose' ? otherCode : code);
          expect(routing?.organisationId, expectedOrganisation);
          expect(settings.operatorEmail, email);
          final token = await OnePubTokenStore().load();
          // Never put tokens or response bodies into assertion diagnostics.
          expect(token.isNotEmpty, isTrue);
          final client = HttpClient();
          try {
            final own = await _request(
                client, server, '/api/organisation/details', token);
            expect(own.status, HttpStatus.ok);
            expect(own.body['obfuscatedId'] == expectedOrganisation, isTrue,
                reason: 'Authenticated organisation must match SAML routing');
            final member =
                await _request(client, server, '/api/member/whoami', token);
            expect(member.status, HttpStatus.ok);
            expect(member.body['email'] == email, isTrue,
                reason: 'Authenticated identity must match the SAML subject');
            final foreign = await _request(client, server,
                '/api/organisation/details/$foreignOrganisation', token);
            expect(foreign.status, HttpStatus.forbidden,
                reason: 'Credential must not access another organisation');
            const expectedForeignError =
                'You are not permitted to access the requested '
                'organisation.';
            expect(foreign.errorMessage == expectedForeignError, isTrue,
                reason: 'Must be the tenant boundary, not a server error');
          } finally {
            client.close(force: true);
          }
          // Real authorised follow-up: import the just-earned credential into
          // another clean CLI profile. Import calls organisation/details and
          // audit logging, unlike doctor, which can pass on local settings
          // alone.
          final exported = p.join(directory.path, 'earned-token');
          await _command(
              ['export', '--file', exported], commandEnvironment, server);
          final importedPath = p.join(directory.path, 'import-${stage.key}');
          final importedSettings = p.join(importedPath, 'settings');
          await Directory(importedSettings).create(recursive: true);
          await File(p.join(importedSettings, 'onepub.yaml'))
              .writeAsString("onepubUrl: '${server.origin}'\n");
          await _command([
            'import',
            '--file',
            exported
          ], {
            ...commandEnvironment,
            'ONEPUB_PATH': importedSettings,
            '_PUB_TEST_CONFIG_DIR': p.join(importedPath, 'tokens'),
          }, server);
          await File(exported).delete();
          final imported = OnePubSettings(
              pathToSettings: p.join(importedSettings, 'onepub.yaml'));
          expect(imported.obfuscatedOrganisationId, expectedOrganisation);
        }
      });
    });
  },
      skip: Platform.environment['ONEPUB_SAML_BROWSER_E2E'] != 'true'
          ? 'Requires managed candidate server, signed fixture and browser; '
              'run TestDartCliSamlSignIn in onepub-vaadin. '
              'Not a passed E2E test.'
          : false,
      timeout: const Timeout(Duration(minutes: 15)));
}

Future<void> _command(
    List<String> arguments, Map<String, String> environment, Uri server,
    {bool forwardChallenge = false, bool succeeds = true}) async {
  final process = await Process.start(
      Platform.resolvedExecutable, ['run', 'bin/onepub.dart', ...arguments],
      environment: environment, includeParentEnvironment: false);
  final readers = <Future<void>>[
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach((line) {
      if (!forwardChallenge) {
        return;
      }
      final match =
          RegExp(r'https?://[^\s\x1b]+/clilogin/[a-f0-9-]+').firstMatch(line);
      if (match == null) {
        return;
      }
      final link = Uri.parse(match.group(0)!);
      if (link.origin != server.origin) {
        throw StateError('CLI challenge left the managed candidate origin');
      }
      print(link);
    }),
    // Do not relay child diagnostics, which can include a credential.
    process.stderr.drain<void>(),
  ];
  try {
    expect(await process.exitCode.timeout(const Duration(minutes: 6)),
        succeeds ? equals(0) : isNot(0),
        reason: 'CLI ${arguments.first} failed (child output suppressed)');
    await Future.wait(readers).timeout(const Duration(seconds: 10));
  } finally {
    process.kill(ProcessSignal.sigkill);
  }
}

void _failureLane() {
  test('failed SAML browser flow saves no usable CLI credential', () async {
    final source = Platform.environment;
    final server = Uri.parse(assertSafeOnePubTestUrl(
        source['ONEPUB_SAML_E2E_URL']!,
        source: 'negative SAML candidate'));
    expect(server.scheme, 'http');
    expect(['127.0.0.1', 'localhost', '::1'], contains(server.host));
    final directory =
        Directory.systemTemp.createTempSync('onepub-saml-denied-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final settings = Directory(p.join(directory.path, 'settings'))
      ..createSync();
    final tokens = Directory(p.join(directory.path, 'tokens'))..createSync();
    final settingsFile = File(p.join(settings.path, 'onepub.yaml'));
    final original = "onepubUrl: '${server.origin}'\n";
    await settingsFile.writeAsString(original);
    final environment = Map<String, String>.of(source)
      ..removeWhere((key, _) =>
          key.startsWith('ONEPUB_') || key == '_PUB_TEST_CONFIG_DIR')
      ..['ONEPUB_PATH'] = settings.path
      ..['_PUB_TEST_CONFIG_DIR'] = tokens.path;
    print('SSO_BROWSER_STAGE:${source['ONEPUB_SAML_E2E_FAILURE']}');
    await _command(
        ['login', 'sso', source['ONEPUB_SAML_E2E_CODE']!], environment, server,
        forwardChallenge: true, succeeds: false);
    expect(await settingsFile.readAsString() == original, isTrue,
        reason: 'Rejected browser login must not change account settings');
    expect(File(p.join(tokens.path, 'pub-tokens.json')).existsSync(), isFalse);
    await OnePubTokenStore.withPathTo(tokens.path, () async {
      expect((await OnePubTokenStore().credentials).isEmpty, isTrue);
    });
    expect(File(p.join(settings.path, 'login-routing.json')).existsSync(),
        isFalse);
  }, timeout: const Timeout(Duration(minutes: 7)));
}

Future<({int status, Map<String, dynamic> body, String? errorMessage})>
    _request(HttpClient client, Uri server, String path, String token) async {
  final request = await client
      .getUrl(server.resolve(path))
      .timeout(const Duration(seconds: 10));
  request.followRedirects = false;
  request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  request.headers.set(HttpHeaders.userAgentHeader, 'onepub/6.0.0');
  final response = await request.close().timeout(const Duration(seconds: 20));
  final raw = await utf8.decoder
      .bind(response)
      .join()
      .timeout(const Duration(seconds: 20));
  final data = jsonDecode(raw) as Map<String, dynamic>;
  return (
    status: response.statusCode,
    body: (data['body'] as Map<String, dynamic>?) ?? {},
    errorMessage:
        (data['error'] as Map<String, dynamic>?)?['message'] as String?,
  );
}
