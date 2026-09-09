import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:onepub/src/api/api.dart';
import 'package:onepub/src/api/oidc_exchange.dart';
import 'package:onepub/src/auth/ci_provider.dart';
import 'package:onepub/src/auth/oidc_token_acquirer.dart';
import 'package:onepub/src/commands/login.dart';
import 'package:onepub/src/commands/login/trusted.dart';
import 'package:onepub/src/exceptions.dart';
import 'package:onepub/src/my_runner.dart';
import 'package:onepub/src/onepub_settings.dart';
import 'package:onepub/src/util/one_pub_token_store.dart';
import 'package:test/test.dart';

import '../../../../test_settings.dart';

final testUrl = assertSafeOnePubTestUrl('http://localhost:8080');

void main() {
  const assertion = 'header.payload.signature';

  test('trusted is a login subcommand', () {
    final login = OnePubLoginCommand();
    expect(login.subcommands, contains('trusted'));
    expect(login.subcommands, isNot(contains('oidc')));
    expect(
        login.subcommands['trusted']!.description,
        'Log in from CI/CD without storing a OnePub token. '
        'Requires trusted publishing to be configured in OnePub.');
  });

  test('bare login is normalized to the browser login method', () {
    expect(MyRunner.normalizeArgs(['login']), ['login', 'browser']);
    expect(
      MyRunner.normalizeArgs(['--debug', 'login']),
      ['--debug', 'login', 'browser'],
    );
    expect(
      MyRunner.normalizeArgs(['login', 'trusted']),
      ['login', 'trusted'],
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
    final command = TrustedLoginCommand(
      environment: {'GITHUB_ACTIONS': 'true'},
      acquirer: acquirer,
      exchangeApi: exchange,
      api: api,
      tokenStore: tokenStore,
    );
    final runner = CommandRunner<int>('onepub-test', 'test')
      ..addCommand(command);

    await OnePubSettings.withPathTo<void>(temp.path, () async {
      OnePubSettings.use().onepubUrl = testUrl;
      expect(await runner.run(['trusted']), 0);

      expect(acquirer.provider, CiProvider.githubActions);
      expect(acquirer.audience, testUrl);
      expect(exchange.assertion, assertion);
      expect(exchange.audience, isNull);
      expect(api.checkedVersion, isTrue);
      expect(tokenStore.url, '$testUrl/api/organisation/');
      expect(tokenStore.token, 'short-lived-onepub-token');
      expect(OnePubSettings.use().organisationName, isEmpty);
      expect(OnePubSettings.use().operatorEmail, isEmpty);
    });
  });

  test('trusted login installs without changing login settings', () async {
    final temp = Directory.systemTemp.createTempSync('onepub-oidc-publish-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final acquirer = _FakeAcquirer(assertion);
    final exchange = _FakeExchangeApi();
    final api = _FakeApi();
    final tokenStore = _FakeTokenStore();
    final command = TrustedLoginCommand(
      environment: {'GITHUB_ACTIONS': 'true'},
      acquirer: acquirer,
      exchangeApi: exchange,
      api: api,
      tokenStore: tokenStore,
    );
    final runner = CommandRunner<int>('onepub-test', 'test')
      ..addCommand(command);

    await OnePubSettings.withPathTo<void>(temp.path, () async {
      OnePubSettings.use().onepubUrl = testUrl;
      final settings = OnePubSettings.use()
        ..onepubUrl = 'http://localhost:8080'
        ..operatorEmail = 'existing@example.test'
        ..obfuscatedOrganisationId = 'existing-organisation'
        ..organisationName = 'Existing Organisation';
      await settings.save();

      expect(await runner.run(['trusted']), 0);

      expect(acquirer.provider, CiProvider.githubActions);
      expect(acquirer.audience, 'http://localhost:8080');
      expect(exchange.assertion, assertion);
      expect(exchange.audience, isNull);
      expect(api.checkedVersion, isTrue);
      expect(tokenStore.url, '$testUrl/api/organisation/');
      expect(tokenStore.token, 'short-lived-onepub-token');
      expect(settings.operatorEmail, 'existing@example.test');
      expect(settings.obfuscatedOrganisationId, 'existing-organisation');
      expect(settings.organisationName, 'Existing Organisation');
      expect(settings.onepubUrl, 'http://localhost:8080');
    });
  });

  test('acquires all package publisher providers', () async {
    for (final provider in [
      CiProvider.githubActions,
      CiProvider.gitlabCi,
      CiProvider.azurePipelines,
      CiProvider.bitbucketPipelines,
      CiProvider.circleCi,
    ]) {
      final temp = Directory.systemTemp.createTempSync('onepub-oidc-provider-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final acquirer = _FakeAcquirer(assertion);
      final api = _FakeApi();
      final runner = CommandRunner<int>('onepub-test', 'test')
        ..addCommand(TrustedLoginCommand(
          environment: const {},
          acquirer: acquirer,
          exchangeApi: _FakeExchangeApi(),
          api: api,
          tokenStore: _FakeTokenStore(),
        ));

      await OnePubSettings.withPathTo<void>(temp.path, () async {
        final settings = OnePubSettings.use()
          ..onepubUrl = 'http://localhost:8080';
        await settings.save();

        expect(
            await runner.run([
              'trusted',
              '--provider',
              provider.id,
            ]),
            0);
      });

      expect(acquirer.provider, provider);
      expect(acquirer.audience, 'http://localhost:8080');
    }
  });

  test('uses a generic JWT from ONEPUB_OIDC_TOKEN without CI detection',
      () async {
    final temp = Directory.systemTemp.createTempSync('onepub-oidc-generic-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final acquirer = _FakeAcquirer('must.not.be-used');
    final exchange = _FakeExchangeApi();
    final runner = CommandRunner<int>('onepub-test', 'test')
      ..addCommand(TrustedLoginCommand(
        environment: {onepubOidcTokenEnv: assertion},
        acquirer: acquirer,
        exchangeApi: exchange,
        api: _FakeApi(),
        tokenStore: _FakeTokenStore(),
      ));

    await OnePubSettings.withPathTo<void>(temp.path, () async {
      OnePubSettings.use().onepubUrl = testUrl;
      expect(await runner.run(['trusted']), 0);
    });

    expect(exchange.assertion, assertion);
    expect(acquirer.provider, isNull);
  });

  test('rejects multiple explicit JWT sources', () async {
    final runner = CommandRunner<int>('onepub-test', 'test')
      ..addCommand(TrustedLoginCommand(
        environment: {'CUSTOM_TOKEN': assertion},
        acquirer: _FakeAcquirer(assertion),
        exchangeApi: _FakeExchangeApi(),
        api: _FakeApi(),
        tokenStore: _FakeTokenStore(),
      ));

    await expectLater(
      runner.run([
        'trusted',
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
      hostedUrl: '$testUrl/api/organisation/',
      expiresAt: DateTime.utc(2026, 8, 7, 12),
    );
  }
}

class _FakeApi extends API {
  var checkedVersion = false;

  @override
  Future<void> checkVersion() async {
    checkedVersion = true;
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
