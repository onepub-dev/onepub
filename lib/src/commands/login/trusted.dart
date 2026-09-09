import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dcli_terminal/dcli_terminal.dart';

import '../../api/api.dart';
import '../../api/oidc_exchange.dart';
import '../../auth/ci_provider.dart';
import '../../auth/oidc_token_acquirer.dart';
import '../../auth/oidc_token_reader.dart';
import '../../exceptions.dart';
import '../../onepub_settings.dart';
import '../../util/one_pub_token_store.dart';

class TrustedLoginCommand extends Command<int> {
  TrustedLoginCommand({
    Map<String, String>? environment,
    OidcTokenAcquirer? acquirer,
    OidcExchangeApi? exchangeApi,
    OidcTokenReader? tokenReader,
    API? api,
    OnePubTokenStore? tokenStore,
  })  : environment = environment ?? Platform.environment,
        acquirer = acquirer ??
            OidcTokenAcquirer(environment: environment ?? Platform.environment),
        exchangeApi = exchangeApi ?? OidcExchangeApi(),
        tokenReader = tokenReader ??
            OidcTokenReader(environment: environment ?? Platform.environment),
        api = api ?? API(),
        tokenStore = tokenStore ?? OnePubTokenStore() {
    argParser
      ..addFlag(
        'publish-only',
        negatable: false,
        help: 'Install the publishing token without requesting organisation '
            'details. Required for package-scoped trusted publishers.',
      )
      ..addOption(
        'provider',
        allowed: CiProvider.values.map((provider) => provider.id),
        allowedHelp: {
          for (final provider in CiProvider.values)
            provider.id: provider.displayName,
        },
        help: 'Override CI provider auto-detection.',
      )
      ..addOption(
        'audience',
        help: 'Audience configured on the OnePub trusted issuer profile. '
            'Defaults to the configured OnePub server URL.',
      )
      ..addOption(
        'token-env',
        valueHelp: 'variable',
        help: 'Read a pre-obtained OIDC JWT from an environment variable.',
      )
      ..addFlag(
        'token-stdin',
        negatable: false,
        help: 'Read a pre-obtained OIDC JWT from standard input.',
      )
      ..addOption(
        'token-file',
        valueHelp: 'path',
        help: 'Read a pre-obtained OIDC JWT from a file.',
      );
  }

  final Map<String, String> environment;
  final OidcTokenAcquirer acquirer;
  final OidcExchangeApi exchangeApi;
  final OidcTokenReader tokenReader;
  final API api;
  final OnePubTokenStore tokenStore;

  @override
  String get description => 'Log in from CI/CD without storing a OnePub token. '
      'Requires trusted publishing to be configured in OnePub.';

  @override
  String get name => 'trusted';

  @override
  Future<int> run() async {
    try {
      final audience = (argResults!['audience'] as String?) ??
          _withoutTrailingSlash(OnePubSettings.use().onepubWebUrl);
      final providerOption = argResults!['provider'] as String?;
      final provider =
          providerOption == null ? null : CiProvider.parse(providerOption);
      final assertion = await _assertion(provider, audience);

      await api.checkVersion();
      final exchange = await exchangeApi.exchange(
        assertion: assertion,
      );
      if (argResults!['publish-only'] as bool) {
        await tokenStore.addToken(
          onepubApiUrl: exchange.hostedUrl,
          onepubToken: exchange.accessToken,
        );
        print(blue('Publishing token installed '
            '(expires ${exchange.expiresAt.toUtc()}).'));
        return 0;
      }

      final organisation = await api.fetchOrganisation(exchange.accessToken);
      if (!organisation.success) {
        throw ExitException(
          exitCode: 1,
          message: organisation.errorMessage ??
              'Unable to read the organisation for the issued token.',
        );
      }

      final settings = OnePubSettings.use()
        ..operatorEmail = 'OIDC workload'
        ..obfuscatedOrganisationId = organisation.obfuscatedId!
        ..organisationName = organisation.name!;
      await settings.save();

      await tokenStore.addToken(
        onepubApiUrl: exchange.hostedUrl,
        onepubToken: exchange.accessToken,
      );

      print(blue('Successfully logged into ${organisation.name} with a '
          'short-lived token (expires ${exchange.expiresAt.toUtc()}).'));
      return 0;
    } on ExitException {
      rethrow;
    } on FormatException catch (error) {
      throw ExitException(exitCode: 1, message: error.message);
    }
  }

  static String _withoutTrailingSlash(String value) =>
      value.endsWith('/') ? value.substring(0, value.length - 1) : value;

  Future<String> _assertion(CiProvider? provider, String audience) async {
    final tokenEnv = argResults!['token-env'] as String?;
    final tokenStdin = argResults!['token-stdin'] as bool;
    final tokenFile = argResults!['token-file'] as String?;
    final explicitSources = [
      tokenEnv != null,
      tokenStdin,
      tokenFile != null,
    ].where((selected) => selected).length;
    if (explicitSources > 1) {
      throw const FormatException(
        'Pass only one of --token-env, --token-stdin, or --token-file.',
      );
    }

    if (tokenEnv != null) {
      return tokenReader.fromEnvironment(tokenEnv);
    }
    if (tokenStdin) {
      return tokenReader.fromStandardInput();
    }
    if (tokenFile != null) {
      return tokenReader.fromFile(tokenFile);
    }

    if (provider == null) {
      final supplied = environment[onepubOidcTokenEnv];
      if (supplied != null && supplied.isNotEmpty) {
        return OidcTokenAcquirer.validate(supplied);
      }
    }

    final detected = CiProviderDetector(environment: environment)
        .requireSingle(override: provider);
    return acquirer.acquire(detected, audience);
  }
}
