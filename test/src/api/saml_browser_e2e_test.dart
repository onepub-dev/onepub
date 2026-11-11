import 'dart:io';

import 'package:onepub/src/my_runner.dart';
import 'package:onepub/src/onepub_settings.dart';
import 'package:onepub/src/util/login_persistence.dart';
import 'package:onepub/src/util/one_pub_token_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// The server's Selenium acceptance lane drives the printed URLs through a real
// browser and signed SAML fixture. No test endpoint completes these challenges.
void main() {
  test('CLI commands complete real browser SAML against the candidate server',
      () async {
    final environment = Platform.environment;
    final server = Uri.parse(environment['ONEPUB_SAML_E2E_URL']!);
    expect(server.scheme, 'http');
    expect(['127.0.0.1', 'localhost', '::1'], contains(server.host));
    final code = environment['ONEPUB_SAML_E2E_CODE']!;
    final organisationId = environment['ONEPUB_SAML_E2E_ORGANISATION']!;
    final email = environment['ONEPUB_SAML_E2E_EMAIL']!;
    final directory = Directory.systemTemp.createTempSync('onepub-saml-e2e-');
    addTearDown(() => directory.deleteSync(recursive: true));
    await OnePubSettings.withPathTo(p.join(directory.path, 'settings'),
        () async {
      final settings = OnePubSettings.use()..onepubUrl = server.toString();
      await settings.save();
      await OnePubTokenStore.withPathTo(p.join(directory.path, 'tokens'),
          () async {
        final commands = <String, List<String>>{
          'first': ['login'],
          'explicit': ['login', 'sso', code],
          'remembered': ['login'],
          'choose': ['login', '--choose'],
        };
        for (final stage in commands.entries) {
          // Only a public stage label is emitted. The CLI prints its normal
          // browser URL; tokens are checked locally and never printed.
          print('SSO_BROWSER_STAGE:${stage.key}');
          final runner = MyRunner(stage.value, 'onepub', 'test');
          expect(await runner.run(runner.args), 0);
          final persistence = LoginPersistence(settings);
          final routing =
              await persistence.preferences.load(persistence.server);
          expect(routing?.method, 'sso');
          expect(routing?.organisationCode, code);
          expect(routing?.organisationId, organisationId);
          expect(settings.operatorEmail, email);
          final token = await OnePubTokenStore().load();
          expect(token.isNotEmpty, isTrue);
          final client = HttpClient();
          try {
            final request = await client
                .getUrl(server.resolve('/api/organisation/details'));
            request.headers
                .set(HttpHeaders.authorizationHeader, 'Bearer $token');
            request.headers.set(HttpHeaders.userAgentHeader, 'onepub/6.0.0');
            final response = await request.close();
            expect(response.statusCode, HttpStatus.ok);
            await response.drain<void>();
          } finally {
            client.close(force: true);
          }
        }
      });
    });
  },
      skip: Platform.environment['ONEPUB_SAML_BROWSER_E2E'] != 'true',
      timeout: const Timeout(Duration(minutes: 15)));
}
