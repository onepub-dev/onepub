import 'dart:io';

import 'package:onepub/src/auth/ci_provider.dart';
import 'package:onepub/src/auth/oidc_http.dart';
import 'package:onepub/src/auth/oidc_token_acquirer.dart';
import 'package:test/test.dart';

void main() {
  const jwt = 'header.payload.signature';

  test('GitHub requests an audience-bound token', () async {
    final http = _FakeHttp({'value': jwt});
    final acquirer = OidcTokenAcquirer(
      environment: {
        'ACTIONS_ID_TOKEN_REQUEST_URL': 'https://github.example/token?x=1',
        'ACTIONS_ID_TOKEN_REQUEST_TOKEN': 'request-secret',
      },
      http: http,
    );

    expect(
      await acquirer.acquire(CiProvider.githubActions, 'onepub-audience'),
      jwt,
    );
    expect(http.method, 'GET');
    expect(http.uri!.queryParameters['x'], '1');
    expect(http.uri!.queryParameters['audience'], 'onepub-audience');
    expect(http.headers['Authorization'], 'Bearer request-secret');
  });

  test('Azure uses its service connection token endpoint', () async {
    final http = _FakeHttp({'oidcToken': jwt});
    final acquirer = OidcTokenAcquirer(
      environment: {
        'SYSTEM_OIDCREQUESTURI': 'https://azure.example/token',
        'SYSTEM_ACCESSTOKEN': 'system-secret',
        'AZURESUBSCRIPTION_SERVICE_CONNECTION_ID': 'connection-id',
      },
      http: http,
    );

    expect(
      await acquirer.acquire(CiProvider.azurePipelines, 'ignored-by-azure'),
      jwt,
    );
    expect(http.method, 'POST');
    expect(http.uri!.queryParameters['api-version'], '7.1');
    expect(http.uri!.queryParameters['serviceConnectionId'], 'connection-id');
    expect(http.uri!.queryParameters, isNot(contains('audience')));
    expect(http.headers['Authorization'], 'Bearer system-secret');
  });

  test('reads provider-supplied fixed token variables', () async {
    final bitbucket = OidcTokenAcquirer(
      environment: {'BITBUCKET_STEP_OIDC_TOKEN': jwt},
    );
    final circle = OidcTokenAcquirer(
      environment: {'CIRCLE_OIDC_TOKEN_V2': jwt},
    );

    expect(
      await bitbucket.acquire(CiProvider.bitbucketPipelines, 'audience'),
      jwt,
    );
    expect(await circle.acquire(CiProvider.circleCi, 'audience'), jwt);
  });

  test('Buildkite requests a token from the local agent', () async {
    String? executable;
    List<String>? arguments;
    final acquirer = OidcTokenAcquirer(
      environment: const {},
      processRunner: (command, commandArguments) async {
        executable = command;
        arguments = commandArguments;
        return ProcessResult(1, 0, '$jwt\n', '');
      },
    );

    expect(await acquirer.acquire(CiProvider.buildkite, 'audience'), jwt);
    expect(executable, 'buildkite-agent');
    expect(arguments, ['oidc', 'request-token', '--audience', 'audience']);
  });

  test('Google Cloud Build requests a metadata identity token', () async {
    Uri? requestedUri;
    Map<String, String>? requestedHeaders;
    final acquirer = OidcTokenAcquirer(
      environment: const {},
      textGetter: (uri, headers) async {
        requestedUri = uri;
        requestedHeaders = headers;
        return jwt;
      },
    );

    expect(
      await acquirer.acquire(CiProvider.googleCloudBuild, 'audience'),
      jwt,
    );
    expect(requestedUri!.queryParameters['audience'], 'audience');
    expect(requestedHeaders, {'Metadata-Flavor': 'Google'});
  });

  test('generic token is accepted for externally integrated providers',
      () async {
    for (final provider in [
      CiProvider.gitlabCi,
      CiProvider.jenkins,
      CiProvider.teamCity,
      CiProvider.harness,
      CiProvider.travisCi,
      CiProvider.awsCodeBuild,
    ]) {
      final acquirer = OidcTokenAcquirer(
        environment: {onepubOidcTokenEnv: jwt},
      );
      expect(await acquirer.acquire(provider, 'audience'), jwt);
    }
  });

  test('rejects values which are not compact JWTs', () {
    expect(
      () => OidcTokenAcquirer.validate('not-a-jwt'),
      throwsFormatException,
    );
  });
}

class _FakeHttp extends OidcHttpClient {
  _FakeHttp(this.responseBody);

  final Map<String, dynamic> responseBody;
  String? method;
  Uri? uri;
  Map<String, String> headers = {};

  @override
  Future<OidcHttpResponse> send({
    required String method,
    required Uri uri,
    Map<String, String> headers = const {},
    Map<String, dynamic>? jsonBody,
    bool allowBadCertificates = false,
  }) async {
    this.method = method;
    this.uri = uri;
    this.headers = headers;
    return OidcHttpResponse(200, responseBody);
  }
}
