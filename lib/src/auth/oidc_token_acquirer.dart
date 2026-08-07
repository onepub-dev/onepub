import 'dart:convert';
import 'dart:io';

import 'ci_provider.dart';
import 'oidc_http.dart';

const onepubOidcTokenEnv = 'ONEPUB_OIDC_TOKEN';

typedef OidcProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);
typedef OidcTextGetter = Future<String> Function(
  Uri uri,
  Map<String, String> headers,
);

class OidcTokenAcquirer {
  OidcTokenAcquirer({
    Map<String, String>? environment,
    OidcHttpClient? http,
    OidcProcessRunner? processRunner,
    OidcTextGetter? textGetter,
  })  : environment = environment ?? Platform.environment,
        http = http ?? const OidcHttpClient(),
        processRunner = processRunner ?? Process.run,
        textGetter = textGetter ?? _plainGet;

  final Map<String, String> environment;
  final OidcHttpClient http;
  final OidcProcessRunner processRunner;
  final OidcTextGetter textGetter;

  Future<String> acquire(CiProvider provider, String audience) async =>
      switch (provider) {
        CiProvider.githubActions => _github(audience),
        CiProvider.azurePipelines => _azure(),
        CiProvider.bitbucketPipelines =>
          _requiredAny(['BITBUCKET_STEP_OIDC_TOKEN']),
        CiProvider.circleCi =>
          _requiredAny(['CIRCLE_OIDC_TOKEN_V2', 'CIRCLE_OIDC_TOKEN']),
        CiProvider.buildkite => _buildkite(audience),
        CiProvider.googleCloudBuild => _googleCloudBuild(audience),
        CiProvider.gitlabCi ||
        CiProvider.jenkins ||
        CiProvider.teamCity ||
        CiProvider.harness ||
        CiProvider.travisCi ||
        CiProvider.awsCodeBuild =>
          _requiredAny([onepubOidcTokenEnv]),
      };

  Future<String> _github(String audience) async {
    final requestUrl = _required('ACTIONS_ID_TOKEN_REQUEST_URL');
    final requestToken = _required('ACTIONS_ID_TOKEN_REQUEST_TOKEN');
    final uri = Uri.parse(requestUrl).replace(queryParameters: {
      ...Uri.parse(requestUrl).queryParameters,
      'audience': audience,
    });
    final response = await http.send(
      method: 'GET',
      uri: uri,
      headers: {'Authorization': 'Bearer $requestToken'},
    );
    return _responseToken(response, 'value', 'GitHub Actions');
  }

  Future<String> _azure() async {
    final requestUrl = _required('SYSTEM_OIDCREQUESTURI');
    final accessToken = _required('SYSTEM_ACCESSTOKEN');
    final serviceConnectionId =
        _required('AZURESUBSCRIPTION_SERVICE_CONNECTION_ID');
    final uri = Uri.parse(requestUrl).replace(queryParameters: {
      ...Uri.parse(requestUrl).queryParameters,
      'api-version': '7.1',
      'serviceConnectionId': serviceConnectionId,
    });
    final response = await http.send(
      method: 'POST',
      uri: uri,
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
    );
    return _responseToken(response, 'oidcToken', 'Azure DevOps');
  }

  Future<String> _buildkite(String audience) async {
    final result = await processRunner(
      'buildkite-agent',
      ['oidc', 'request-token', '--audience', audience],
    );
    if (result.exitCode != 0) {
      throw const FormatException('Buildkite could not issue an OIDC token.');
    }
    return _validate('${result.stdout}');
  }

  Future<String> _googleCloudBuild(String audience) async {
    final uri = Uri.parse(
      'http://metadata.google.internal/computeMetadata/v1/instance/'
      'service-accounts/default/identity',
    ).replace(queryParameters: {'audience': audience, 'format': 'full'});
    final response = await textGetter(uri, {'Metadata-Flavor': 'Google'});
    return _validate(response);
  }

  static Future<String> _plainGet(
    Uri uri,
    Map<String, String> headers,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(uri);
      headers.forEach(request.headers.set);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const FormatException(
          'The CI provider could not issue an OIDC token.',
        );
      }
      return await utf8.decoder.bind(response).join();
    } finally {
      client.close(force: true);
    }
  }

  String _responseToken(
      OidcHttpResponse response, String field, String provider) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FormatException('$provider could not issue an OIDC token.');
    }
    final token = response.body[field];
    if (token is! String) {
      throw FormatException('$provider returned an invalid OIDC response.');
    }
    return _validate(token);
  }

  String _requiredAny(List<String> names) {
    for (final name in names) {
      final value = environment[name];
      if (value != null && value.isNotEmpty) {
        return _validate(value);
      }
    }
    throw FormatException(
        'No OIDC JWT was found. Configure ${names.join(' or ')} '
        'or use --token-env, --token-stdin, or --token-file.');
  }

  String _required(String name) {
    final value = environment[name];
    if (value == null || value.isEmpty) {
      throw FormatException('The CI provider did not supply $name.');
    }
    return value;
  }

  static String validate(String value) => _validate(value);

  static String _validate(String value) {
    final token = value.trim();
    if (token.isEmpty || token.length > 32768 || token.split('.').length != 3) {
      throw const FormatException('The supplied OIDC token is not a JWT.');
    }
    return token;
  }
}
