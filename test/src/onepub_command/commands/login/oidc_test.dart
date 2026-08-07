import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:onepub/src/api/api.dart';
import 'package:onepub/src/api/oidc_exchange.dart';
import 'package:onepub/src/api/organisation.dart';
import 'package:onepub/src/auth/ci_provider.dart';
import 'package:onepub/src/auth/oidc_token_acquirer.dart';
import 'package:onepub/src/commands/login.dart';
import 'package:onepub/src/commands/login/oidc.dart';
import 'package:onepub/src/exceptions.dart';
import 'package:onepub/src/my_runner.dart';
import 'package:onepub/src/onepub_settings.dart';
import 'package:onepub/src/util/one_pub_token_store.dart';
import 'package:test/test.dart';

void main() {
  const assertion = 'header.payload.signature';

  test('oidc is a login subcommand', () {
    expect(OnePubLoginCommand().subcommands, contains('oidc'));
  });

  test('bare login is normalized to the browser login method', () {
    expect(MyRunner.normalizeArgs(['login']), ['login', 'browser']);
    expect(
      MyRunner.normalizeArgs(['--debug', 'login']),
      ['--debug', 'login', 'browser'],
    );
    expect(
      MyRunner.normalizeArgs(['login', 'oidc']),
      ['login', 'oidc'],
    );
  });

  test('auto-detects the provider, exchanges, and installs the token',
      () async {
    final temp = Directory.systemTemp.createTempSync('onepub-oidc-login-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final acquirer = _FakeAcquirer(assertion);
    final exchange = _FakeExchangeApi();
    final api = _FakeApi();
    final tokenStore = _FakeTokenStore();
    final command = OidcLoginCommand(
      environment: {'GITHUB_ACTIONS': 'true'},
      acquirer: acquirer,
      exchangeApi: exchange,
      api: api,
      tokenStore: tokenStore,
    );
    final runner = CommandRunner<int>('onepub-test', 'test')
      ..addCommand(command);

    await OnePubSettings.withPathTo<void>(temp.path, () async {
      expect(await runner.run(['oidc']), 0);

      expect(acquirer.provider, CiProvider.githubActions);
      expect(acquirer.audience, 'https://onepub.dev');
      expect(exchange.assertion, assertion);
      expect(exchange.audience, isNull);
      expect(api.checkedVersion, isTrue);
      expect(api.fetchedWith, 'short-lived-onepub-token');
      expect(tokenStore.url, 'https://packages.example/api/organisation/');
      expect(tokenStore.token, 'short-lived-onepub-token');
      expect(OnePubSettings.use().organisationName, 'Test Organisation');
      expect(OnePubSettings.use().operatorEmail, 'OIDC workload');
    });
  });

  test('uses a generic JWT from ONEPUB_OIDC_TOKEN without CI detection',
      () async {
    final temp = Directory.systemTemp.createTempSync('onepub-oidc-generic-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final acquirer = _FakeAcquirer('must.not.be-used');
    final exchange = _FakeExchangeApi();
    final runner = CommandRunner<int>('onepub-test', 'test')
      ..addCommand(OidcLoginCommand(
        environment: {onepubOidcTokenEnv: assertion},
        acquirer: acquirer,
        exchangeApi: exchange,
        api: _FakeApi(),
        tokenStore: _FakeTokenStore(),
      ));

    await OnePubSettings.withPathTo<void>(temp.path, () async {
      expect(await runner.run(['oidc']), 0);
    });

    expect(exchange.assertion, assertion);
    expect(acquirer.provider, isNull);
  });

  test('rejects multiple explicit JWT sources', () async {
    final runner = CommandRunner<int>('onepub-test', 'test')
      ..addCommand(OidcLoginCommand(
        environment: {'CUSTOM_TOKEN': assertion},
        acquirer: _FakeAcquirer(assertion),
        exchangeApi: _FakeExchangeApi(),
        api: _FakeApi(),
        tokenStore: _FakeTokenStore(),
      ));

    await expectLater(
      runner.run([
        'oidc',
        '--token-env',
        'CUSTOM_TOKEN',
        '--token-file',
        '/unused',
      ]),
      throwsA(
        isA<ExitException>().having(
          (error) => error.message,
          'message',
          contains('Pass only one'),
        ),
      ),
    );
  });
}

class _FakeAcquirer extends OidcTokenAcquirer {
  _FakeAcquirer(this.result) : super(environment: const {});

  final String result;
  CiProvider? provider;
  String? audience;

  @override
  Future<String> acquire(CiProvider provider, String audience) async {
    this.provider = provider;
    this.audience = audience;
    return result;
  }
}

class _FakeExchangeApi extends OidcExchangeApi {
  String? assertion;
  String? audience;

  @override
  Future<OidcExchangeResult> exchange({
    required String assertion,
    String? audience,
  }) async {
    this.assertion = assertion;
    this.audience = audience;
    return OidcExchangeResult(
      accessToken: 'short-lived-onepub-token',
      hostedUrl: 'https://packages.example/api/organisation/',
      expiresAt: DateTime.utc(2026, 8, 7, 12),
    );
  }
}

class _FakeApi extends API {
  var checkedVersion = false;
  String? fetchedWith;

  @override
  Future<void> checkVersion() async {
    checkedVersion = true;
  }

  @override
  Future<Organisation> fetchOrganisation(String onepubToken) async {
    fetchedWith = onepubToken;
    return Organisation.success(
      name: 'Test Organisation',
      obfuscatedId: 'organisation',
    );
  }
}

class _FakeTokenStore extends OnePubTokenStore {
  String? url;
  String? token;

  @override
  Future<void> addToken({
    required String onepubApiUrl,
    required String onepubToken,
  }) async {
    url = onepubApiUrl;
    token = onepubToken;
  }
}
