import 'dart:convert';
import 'dart:io';

import 'package:onepub/src/util/one_pub_token_store.dart';
import 'package:path/path.dart' as p;
import 'package:revault_api/revault_api.dart';

const betaFixtureClientId = 'onepub-beta-fixture-operator';
const betaFixtureSecretPath = '/beta/provisioning/fixture_client_secret';

/// Reads the operator secret from an already open reVault session and creates
/// credentials for one disposable assessment organisation.
Future<Map<String, dynamic>> issueBetaAssessmentCredentials(
    String origin, String name,
    {Future<String> Function()? readSecret,
    Future<Map<String, dynamic>> Function(String, Map<String, String>)?
        exchange}) async {
  try {
    return await _issue(origin, name, readSecret, exchange);
  } on Object {
    throw StateError('Beta assessment credentials unavailable.');
  }
}

Future<Map<String, dynamic>> _issue(
    String origin,
    String name,
    Future<String> Function()? readSecret,
    Future<Map<String, dynamic>> Function(String, Map<String, String>)?
        exchange) async {
  if (origin != 'https://beta.onepub.dev' ||
      !RegExp(r'^onepub_staging_test_[A-Za-z0-9_-]{1,80}$').hasMatch(name)) {
    throw StateError(
        'A beta target and disposable assessment name are required.');
  }
  final secret = await (readSecret?.call() ?? _operatorSecret());
  if (secret.isEmpty || secret.contains(RegExp(r'[\r\n]'))) {
    throw StateError('Invalid beta fixture credential.');
  }
  final request = exchange ?? (path, fields) => _post(origin, path, fields);
  final root = await request('/api/provisioning/oauth/token', {
    'grant_type': 'client_credentials',
    'scope': 'test:fixtures',
    'client_id': betaFixtureClientId,
    'client_secret': secret,
  });
  final access = root['access_token'];
  if (access is! String || access.isEmpty || root['scope'] != 'test:fixtures') {
    throw StateError('Beta fixture authentication failed.');
  }
  final created = await request('/api/scim/v2/TestOrganisations', {
    'access_token': access,
    'name': name,
  });
  final token = created['onepubToken'];
  final refresh = created['testFixtureRefreshToken'];
  if (created['organisationName'] != name ||
      token is! String ||
      token.isEmpty ||
      refresh is! String ||
      refresh.isEmpty ||
      created['testFixtureScopes'] != 'test:fixtures') {
    throw StateError('Beta fixture organisation response is incomplete.');
  }
  return {
    'onepubUrl': origin,
    'clientId': betaFixtureClientId,
    'clientSecret': secret,
    'onepubToken': token,
    'refreshToken': refresh,
    'scopes': 'test:fixtures',
  };
}

Future<String> _operatorSecret() async {
  final home = Platform.environment['HOME'];
  final path = Platform.environment['ONEPUB_BETA_OAUTH_LOCKBOX'] ??
      (home == null
          ? null
          : p.join(home, '.local', 'lockboxes', 'onepub_beta_api_keys.lbox'));
  if (path == null || path.isEmpty) {
    throw StateError('A beta Lockbox path is required.');
  }
  await Revault.load();
  var lockbox = AgentSession.instance.tryAcquireOpenLockbox(path);
  if (lockbox == null) {
    if (home == null || home.isEmpty) {
      throw StateError('HOME is required to locate the reVault vault.');
    }
    final sessionBusAddress = Platform.environment['DBUS_SESSION_BUS_ADDRESS'];
    final vault = Vault.open(
      pathTo: p.join(home, '.local', 'share', 'lockbox', 'vault'),
      platformCredentialContext:
          Platform.isLinux && (sessionBusAddress?.isNotEmpty ?? false)
              ? PlatformCredentialContext.linux(
                  sessionBusAddress: sessionBusAddress!,
                )
              : null,
    );
    try {
      lockbox = Lockbox.open(path, vault: vault);
    } finally {
      vault.close();
    }
  }
  try {
    if (lockbox.variableSensitivity(betaFixtureSecretPath) != 'secret') {
      throw StateError('Beta fixture secret is unavailable.');
    }
    final value = lockbox.withSecretVariable(betaFixtureSecretPath,
        (bytes) => utf8.decode(bytes, allowMalformed: false));
    if (value == null) {
      throw StateError('Beta fixture secret is unavailable.');
    }
    return value;
  } finally {
    lockbox.close();
  }
}

Future<Map<String, dynamic>> _post(
    String origin, String path, Map<String, String> fields) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final request = await client.postUrl(Uri.parse('$origin$path'));
    request.followRedirects = false;
    if (path.endsWith('/token')) {
      request.headers.contentType =
          ContentType.parse('application/x-www-form-urlencoded');
      request.write(Uri(queryParameters: fields).query);
    } else {
      request.headers.contentType = ContentType.parse('application/scim+json');
      request.headers.set(
          HttpHeaders.authorizationHeader, 'Bearer ${fields['access_token']}');
      request.write(jsonEncode({
        'schemas': ['urn:onepub:params:scim:schemas:test:2.0:Organisation'],
        'name': fields['name'],
        'plan': 'enterprise',
        'dedicatedOwner': false,
      }));
    }
    final response = await request.close().timeout(const Duration(seconds: 45));
    if (response.statusCode != 200) {
      throw StateError(
          'Beta fixture request failed (HTTP ${response.statusCode}).');
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 45))) {
      if (bytes.length + chunk.length > 65536) {
        throw StateError('Beta fixture response exceeded the limit.');
      }
      bytes.addAll(chunk);
    }
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  } finally {
    client.close(force: true);
  }
}

Future<void> storeAssessmentToken(
        String directory, String origin, String token) =>
    OnePubTokenStore.withPathTo(
        directory,
        () => OnePubTokenStore()
            .addToken(onepubApiUrl: origin, onepubToken: token));
