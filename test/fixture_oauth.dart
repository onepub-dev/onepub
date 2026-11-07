import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:onepub/src/api/onepub_token.dart';
import 'package:onepub/src/onepub_settings.dart';
import 'package:onepub/src/util/one_pub_token_store.dart';
import 'package:onepub/src/util/send_command.dart';
import 'scim_test_client.dart';
import 'test_settings.dart';

/// Test-only OAuth ownership. Member tokens are local actor selectors only.
/// A harness owns rotating grants; Dart test isolates share its authenticated
/// loopback broker rather than copying refresh credentials into each isolate.
class FixtureOAuth {
  static const authorizationKey = 'ONEPUB_TEST_FIXTURE_AUTHORIZATION';
  static const brokerKey = 'ONEPUB_TEST_FIXTURE_BROKER';
  static FixtureOAuth? _local;

  FixtureOAuth._(this.origin, this._clientId, this._clientSecret,
      this._rootActor, String refreshToken) {
    _register(_rootActor, refreshToken);
  }

  final String origin;
  final String _clientId;
  final String _clientSecret;
  final String _rootActor;
  final _clients = <String, ScimTestClient>{};
  final _registeredRefreshTokens = <String>{};

  /// Explicit single-owner setup for harnesses and isolated mock tests.
  static void configure(String onepubUrl, Map<String, dynamic> authorization) {
    final origin = _safeOrigin(onepubUrl);
    if (authorization['onepubUrl'] is! String ||
        _safeOrigin(authorization['onepubUrl'] as String) != origin) {
      throw const ScimTestException(
          'Fixture OAuth seed origin does not match.');
    }
    for (final key in [
      'clientId',
      'clientSecret',
      'refreshToken',
      'onepubToken'
    ]) {
      if (authorization[key] is! String ||
          (authorization[key] as String).isEmpty) {
        throw const ScimTestException('Invalid fixture OAuth authorization.');
      }
    }
    if (!_hasFixtureScope(authorization['scopes'])) {
      throw const ScimTestException('Fixture OAuth scope is required.');
    }
    _local = FixtureOAuth._(
        origin,
        authorization['clientId'] as String,
        authorization['clientSecret'] as String,
        authorization['onepubToken'] as String,
        authorization['refreshToken'] as String);
  }

  static void reset() => _local = null;

  static String _safeOrigin(String url) {
    final uri =
        Uri.parse(assertSafeOnePubTestUrl(url, source: 'fixture OAuth'));
    if (uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const ScimTestException('Invalid fixture OAuth origin.');
    }
    return uri.origin;
  }

  static bool _hasFixtureScope(Object? scopes) =>
      scopes is String && scopes.split(' ').contains('test:fixtures');

  void _register(String actor, String refreshToken) {
    if (!_registeredRefreshTokens.add(refreshToken)) {
      return;
    }
    _clients[actor] = ScimTestClient.refreshToken(
        onepubUrl: origin,
        clientId: _clientId,
        clientSecret: _clientSecret,
        refreshToken: refreshToken);
  }

  Future<String> _access(String url, String actor, bool root) {
    if (_safeOrigin(url) != origin) {
      throw const ScimTestException('Fixture OAuth origin does not match.');
    }
    if (root && actor.isNotEmpty) {
      throw const ScimTestException('Ambiguous fixture OAuth actor.');
    }
    final client = _clients[root ? _rootActor : actor];
    if (client == null) {
      throw const ScimTestException('No fixture OAuth grant for this actor.');
    }
    return client.accessToken();
  }

  void _accept(String url, Map<String, dynamic> body) {
    if (_safeOrigin(url) != origin) {
      throw const ScimTestException('Fixture OAuth origin does not match.');
    }
    final refresh = body['testFixtureRefreshToken'];
    if (refresh == null) {
      return;
    }
    final actor = body['onepubToken'];
    // bind/service-account can return identity metadata without a CLI token.
    // Their subsequent privileged export registers an exact actor grant.
    if (actor == null) {
      return;
    }
    if (actor is! String ||
        actor.isEmpty ||
        refresh is! String ||
        refresh.isEmpty ||
        !_hasFixtureScope(body['testFixtureScopes'])) {
      throw const ScimTestException('Invalid fixture OAuth child grant.');
    }
    // Exporting the root actor yields an attenuated child. Never replace the
    // harness's independently issued root grant with that child.
    if (actor != _rootActor) {
      _register(actor, refresh);
    }
  }

  static Future<String> token(
      {String? actor, bool root = false, String? onepubUrl}) async {
    final settings = OnePubSettings.use();
    final url =
        onepubUrl ?? settings.onepubUrl ?? OnePubSettings.defaultOnePubUrl;
    final selector = actor ?? (root ? '' : await OnePubTokenStore().load());
    final local = _local;
    if (local != null) {
      return await local._access(url, selector, root);
    }
    final result = await _brokerCall({
      'operation': 'token',
      'origin': _safeOrigin(url),
      'actor': selector,
      'root': root,
    });
    final token = result['accessToken'];
    if (token is! String || token.isEmpty) {
      throw const ScimTestException('Invalid fixture OAuth broker response.');
    }
    return token;
  }

  static Future<void> accept(Map<String, dynamic> body,
      {String? onepubUrl}) async {
    if (body['testFixtureRefreshToken'] == null ||
        body['onepubToken'] == null) {
      return;
    }
    final url = onepubUrl ??
        OnePubSettings.use().onepubUrl ??
        OnePubSettings.defaultOnePubUrl;
    final local = _local;
    if (local != null) {
      local._accept(url, body);
    } else {
      await _brokerCall(
          {'operation': 'register', 'origin': _safeOrigin(url), 'body': body});
    }
  }

  static Future<Map<String, dynamic>> _brokerCall(
      Map<String, dynamic> body) async {
    // An explicit malformed broker never falls back to a different authority.
    final encoded = Platform.environment[brokerKey] ??
        await _criticalBroker(body['origin'] as String);
    if (encoded == null) {
      throw const ScimTestException(
          'Fixture OAuth harness authorization is required.');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final config = jsonDecode(encoded) as Map<String, dynamic>;
      final uri = Uri.parse(config['url'] as String);
      if (uri.scheme != 'http' ||
          uri.host != '127.0.0.1' ||
          uri.userInfo.isNotEmpty ||
          uri.path != '/' ||
          uri.hasQuery ||
          uri.hasFragment) {
        throw const ScimTestException('Invalid fixture OAuth broker.');
      }
      return await (() async {
        final request = await client.postUrl(uri);
        request.followRedirects = false;
        request.headers
            .set(HttpHeaders.authorizationHeader, config['secret'] as String);
        request.write(jsonEncode(body));
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          throw const ScimTestException(
              'Fixture OAuth broker rejected request.');
        }
        return await _readJson(response);
      })()
          .timeout(const Duration(seconds: 30));
    } on Object {
      throw const ScimTestException('Fixture OAuth broker request failed.');
    } finally {
      client.close(force: true);
    }
  }

  /// The detached critical-test host publishes only a broker locator here.
  /// Refuse links, another owner, or group/world-accessible state before reads.
  static Future<void> requirePrivateState(Directory state) async {
    if (!Platform.isLinux ||
        FileSystemEntity.typeSync(state.path, followLinks: false) !=
            FileSystemEntityType.directory ||
        await state.resolveSymbolicLinks() != state.absolute.path ||
        (state.statSync().mode & 0x3f) != 0) {
      throw const ScimTestException('Invalid private fixture state.');
    }
    final owner = await Process.run('stat', ['-c', '%u', '--', state.path]);
    final current = await Process.run('id', ['-u']);
    if (owner.exitCode != 0 ||
        current.exitCode != 0 ||
        (owner.stdout as String).trim() != (current.stdout as String).trim()) {
      throw const ScimTestException('Fixture state is owned by another user.');
    }
  }

  static Future<String?> _criticalBroker(String origin) async {
    final state =
        Directory('${Directory.current.path}/.dart_tool/critical_test_server');
    return await readCriticalBroker(state, origin);
  }

  static Future<String?> readCriticalBroker(
      Directory state, String origin) async {
    final file = File('${state.path}/broker.json');
    if (FileSystemEntity.typeSync(file.path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return null;
    }
    await requirePrivateState(state);
    if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
            FileSystemEntityType.file ||
        (file.statSync().mode & 0x3f) != 0 ||
        file.lengthSync() > 65536) {
      throw const ScimTestException('Invalid private fixture broker handoff.');
    }
    final owner = await Process.run('stat', ['-c', '%u', '--', file.path]);
    final current = await Process.run('id', ['-u']);
    if (owner.exitCode != 0 ||
        current.exitCode != 0 ||
        (owner.stdout as String).trim() != (current.stdout as String).trim()) {
      throw const ScimTestException('Invalid fixture broker owner.');
    }
    final handoff =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    if (_safeOrigin(handoff['origin'] as String) != origin) {
      throw const ScimTestException('Fixture broker origin does not match.');
    }
    return handoff['broker'] as String;
  }

  static Future<Map<String, dynamic>> _readJson(
      Stream<List<int>> stream) async {
    final bytes = <int>[];
    await for (final chunk in stream) {
      if (bytes.length + chunk.length > 65536) {
        throw const ScimTestException(
            'Fixture OAuth request exceeds size limit.');
      }
      bytes.addAll(chunk);
    }
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map<String, dynamic>) {
      throw const ScimTestException('Invalid fixture OAuth request.');
    }
    return value;
  }

  /// Called once by the process which launches test workers. Never initialize
  /// independent owners in test isolates from the same rotating seed.
  static Future<FixtureOAuthBroker> startHarness(String onepubUrl,
      {Map<String, dynamic>? authorization}) async {
    if (authorization == null) {
      try {
        authorization = jsonDecode(Platform.environment[authorizationKey] ?? '')
            as Map<String, dynamic>;
      } on Object {
        throw const ScimTestException(
            'Fixture OAuth authorization is required.');
      }
    }
    configure(onepubUrl, authorization);
    final owner = _local!;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final random = Random.secure();
    final secret =
        base64UrlEncode(List.generate(32, (_) => random.nextInt(256)));
    server.listen((request) async {
      try {
        if (request.method != 'POST' ||
            request.uri.path != '/' ||
            request.uri.hasQuery ||
            request.headers.value(HttpHeaders.authorizationHeader) != secret) {
          request.response.statusCode = HttpStatus.forbidden;
          return;
        }
        final body =
            await _readJson(request).timeout(const Duration(seconds: 10));
        final url = body['origin'] as String;
        final Map<String, dynamic> result;
        switch (body['operation']) {
          case 'token':
            result = {
              'accessToken': await owner._access(
                  url, body['actor'] as String, body['root'] as bool)
            };
          case 'register':
            owner._accept(url, body['body'] as Map<String, dynamic>);
            result = {};
          default:
            throw const ScimTestException('Unknown fixture OAuth operation.');
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(result));
      } on Object {
        request.response.statusCode = HttpStatus.forbidden;
      } finally {
        await request.response.close();
      }
    });
    return FixtureOAuthBroker._(server, secret);
  }
}

class FixtureOAuthBroker {
  FixtureOAuthBroker._(this._server, this._secret);
  final HttpServer _server;
  final String _secret;

  Map<String, String> workerEnvironment(Map<String, String> environment) => {
        for (final entry in environment.entries)
          if (entry.key != FixtureOAuth.authorizationKey)
            entry.key: entry.value,
        FixtureOAuth.brokerKey: jsonEncode({
          'url': 'http://127.0.0.1:${_server.port}/',
          'secret': _secret,
        }),
      };

  Future<void> close() async {
    await _server.close(force: true);
    FixtureOAuth.reset();
  }
}

/// Only the six legacy test helpers use CLI envelopes. Product commands retain
/// their usual member authorization through sendCommand.
Future<EndpointResponse> sendFixtureCommand({
  required String command,
  required CommandType commandType,
  String? actor,
  String? onepubUrl,
  String? body,
  Method method = Method.get,
  Duration? timeout,
}) =>
    _sendFixtureCommand(
        command: command,
        commandType: commandType,
        actor: actor,
        onepubUrl: onepubUrl,
        body: body,
        method: method,
        timeout: timeout);

Future<EndpointResponse> _sendFixtureCommand({
  required String command,
  required CommandType commandType,
  String? actor,
  bool root = false,
  String? onepubUrl,
  String? body,
  Method method = Method.get,
  Duration? timeout,
}) async {
  final path = Uri.parse(command).path;
  if (!RegExp(
          r'^test/(?:whoami|member/exportToken/[^/]+/[^/]+|auth/completeCliLogin/[^/]+|package/(?:create|delete)/[^/]+|download/seed/[0-9]+)$')
      .hasMatch(path)) {
    throw ArgumentError('Unsupported fixture helper.');
  }
  final origin = FixtureOAuth._safeOrigin(onepubUrl ??
      OnePubSettings.use().onepubUrl ??
      OnePubSettings.defaultOnePubUrl);
  final token =
      await FixtureOAuth.token(actor: actor, root: root, onepubUrl: origin);
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5)
    ..userAgent = 'onepub 2.15.0';
  final EndpointResponse response;
  try {
    response = await (() async {
      final uri = Uri.parse(origin).resolve('/api/$command');
      if (uri.origin != origin) {
        throw const ScimTestException('Invalid fixture helper origin.');
      }
      final request =
          await client.openUrl(method == Method.post ? 'POST' : 'GET', uri);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(body);
      }
      final result = await request.close();
      final bytes = <int>[];
      await for (final chunk in result) {
        if (bytes.length + chunk.length > 4 * 1024 * 1024) {
          throw const ScimTestException('Fixture response exceeds size limit.');
        }
        bytes.addAll(chunk);
      }
      if (result.statusCode >= 300 && result.statusCode < 400) {
        throw const ScimTestException('Fixture helper redirect rejected.');
      }
      return EndpointResponse(
          result.statusCode, StringBuffer(utf8.decode(bytes)), commandType);
    })()
        .timeout(timeout ?? const Duration(seconds: 30));
  } on ScimTestException {
    rethrow;
  } on Object {
    throw const ScimTestException('Fixture helper request failed.');
  } finally {
    client.close(force: true);
  }
  if (response.success) {
    final envelope = response.parseCli((json) => json);
    final result = envelope.body;
    if (result != null) {
      await FixtureOAuth.accept(result, onepubUrl: origin);
    }
  }
  return response;
}

Future<OnePubToken> exportTestMemberToken({
  required String obfuscatedOrganisationId,
  required String memberEmail,
}) async =>
    OnePubToken(await _sendFixtureCommand(
        command: 'test/member/exportToken/$obfuscatedOrganisationId/'
            '${Uri.encodeComponent(memberEmail)}',
        commandType: CommandType.cli,
        root: true));
