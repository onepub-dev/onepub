import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../onepub_settings.dart';
import 'device_key.dart';

String deviceBase64(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

/// Public enrollment metadata only. Private material remains with the OS key.
class DeviceSession {
  final Uri repository;
  final String deviceId;
  final Directory storage;
  DeviceSession(this.repository, this.deviceId, this.storage);

  static File registry(OnePubSettings settings) => File(
      p.join(p.dirname(settings.pathToSettings), 'device-enrollments.json'));

  static Future<Map<String, dynamic>> readRegistry(
      OnePubSettings settings) async {
    final file = registry(settings);
    if (!await file.exists()) return {};
    final value = jsonDecode(await file.readAsString());
    if (value is! Map<String, dynamic>)
      throw const FormatException('Invalid device registry');
    return value;
  }

  static Future<DeviceSession?> load(
      OnePubSettings settings, Uri repository) async {
    final value = (await readRegistry(settings))[repository.toString()];
    if (value == null) return null;
    validateRepository(repository);
    if (value is! Map<String, dynamic> ||
        value['deviceId'] is! String ||
        value['keyDirectory'] is! String) {
      throw const FormatException('Invalid device enrollment');
    }
    return DeviceSession(repository, value['deviceId'] as String,
        Directory(value['keyDirectory'] as String));
  }

  Map<String, dynamic> get metadata =>
      {'deviceId': deviceId, 'keyDirectory': storage.absolute.path};

  static void validateRepository(Uri uri) {
    if (!uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !uri.path.endsWith('/') ||
        uri.pathSegments.any((s) => s == '.' || s == '..') ||
        (uri.scheme != 'https' &&
            !(uri.scheme == 'http' &&
                (uri.host == 'localhost' ||
                    uri.host == '127.0.0.1' ||
                    uri.host == '::1')))) {
      throw const FormatException('Invalid device repository');
    }
  }

  bool contains(Uri uri) =>
      uri.scheme == repository.scheme &&
      uri.host == repository.host &&
      uri.port == repository.port &&
      uri.userInfo.isEmpty &&
      !uri.hasFragment &&
      !uri.hasQuery &&
      uri.path.startsWith(repository.path) &&
      !uri.pathSegments.any(
          (s) => s == '.' || s == '..' || s.contains('/') || s.contains('\\'));

  Future<Map<String, dynamic>> post(
      String endpoint, Map<String, dynamic> body) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      return await (() async {
        final request = await client.postUrl(repository.resolve(endpoint));
        request.followRedirects = false;
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
        final response = await request.close();
        if (response.statusCode != 200)
          throw const DeviceSessionException('sign_in_required');
        var count = 0;
        final bytes = <int>[];
        await for (final chunk in response) {
          count += chunk.length;
          if (count > 65536)
            throw const FormatException('Oversized device response');
          bytes.addAll(chunk);
        }
        final result = jsonDecode(utf8.decode(bytes));
        if (result is! Map<String, dynamic>)
          throw const FormatException('Invalid device response');
        return result;
      })()
          .timeout(const Duration(seconds: 20));
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> acquire(Map<String, dynamic> request,
      {bool internalCli = false}) async {
    final operation = request['operation'];
    final package = request['package'];
    if (!(internalCli && operation == 'cli' && package == null) &&
        (!['read', 'publish'].contains(operation) ||
            package is! String ||
            package.isEmpty)) {
      throw const FormatException('Invalid operation');
    }
    final fields = <String, dynamic>{
      'deviceId': deviceId,
      'operation': operation,
      if (package != null) 'package': package,
      if (request.containsKey('version')) 'version': request['version'],
      if (request.containsKey('archive')) 'archive': request['archive'],
      if (request.containsKey('attestations'))
        'attestations': request['attestations']
    };
    final challenge = await post('device/challenge', fields);
    final encoded = challenge['challenge'];
    final challengeId = challenge['challengeId'];
    if (encoded is! String || challengeId is! String)
      throw const FormatException('Invalid challenge');
    final bytes = base64Url.decode(base64Url.normalize(encoded));
    final payload = jsonDecode(utf8.decode(bytes));
    if (payload is! Map<String, dynamic> ||
        payload['domain'] != 'onepub-device-grant-v1' ||
        payload['repository-url'] != repository.toString() ||
        payload['nonce'] is! String ||
        (payload['nonce'] as String).isEmpty)
      throw const FormatException('Invalid challenge binding');
    for (final name in [
      'deviceId',
      'operation',
      'package',
      'version',
      'archive',
      'attestations'
    ]) {
      if (!_equal(payload[name], fields[name]))
        throw const FormatException('Challenge does not match request');
    }
    final key = await DeviceKey.open(storage);
    final result = await post('device/exchange', {
      'deviceId': deviceId,
      'challengeId': challengeId,
      'signature': deviceBase64(await key.sign(bytes))
    });
    final expiry = DateTime.tryParse(result['expiresAt'] as String? ?? '');
    if (result['token'] is! String ||
        (result['token'] as String).isEmpty ||
        result['tokenType'] != 'DPoP' ||
        expiry == null ||
        !expiry.isAfter(DateTime.now()))
      throw const FormatException('Invalid device grant');
    return {
      'token': result['token'],
      'tokenType': 'DPoP',
      'expiresAt': result['expiresAt']
    };
  }

  Future<Map<String, dynamic>> prove(Map<String, dynamic> request,
      {bool internalCli = false}) async {
    final uri = Uri.parse(request['uri'] as String);
    final method = request['method'];
    final token = request['token'];
    if (!(contains(uri) || (internalCli && permitsCli(uri))) ||
        method is! String ||
        !RegExp(r'^[A-Z]+$').hasMatch(method) ||
        token is! String ||
        token.isEmpty ||
        (request.containsKey('nonce') && request['nonce'] is! String))
      throw const FormatException('Invalid proof request');
    final key = await DeviceKey.open(storage);
    final header = deviceBase64(utf8.encode(
        jsonEncode({'typ': 'dpop+jwt', 'alg': 'ES256', 'jwk': key.publicJwk})));
    final claims = deviceBase64(utf8.encode(jsonEncode({
      'jti': const Uuid().v4(),
      'htm': method,
      'htu': uri.toString(),
      'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'ath': deviceBase64(sha256.convert(utf8.encode(token)).bytes),
      if (request.containsKey('nonce')) 'nonce': request['nonce']
    })));
    final input = '$header.$claims';
    return {
      'proof': '$input.${deviceBase64(await key.sign(utf8.encode(input)))}'
    };
  }

  bool permitsCli(Uri uri) {
    final api = repository.resolve('../');
    if (uri.scheme != api.scheme ||
        uri.host != api.host ||
        uri.port != api.port ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !uri.path.startsWith(api.path)) return false;
    final endpoint = uri.path.substring(api.path.length);
    return [
          'member/logout',
          'organisation/details',
          'member/whoami',
          'team/list'
        ].contains(endpoint) ||
        RegExp(r'^member/exportToken/[^/]+$').hasMatch(endpoint) ||
        endpoint ==
            'organisation/details/${repository.pathSegments[repository.pathSegments.length - 2]}';
  }

  static bool _equal(Object? a, Object? b) {
    if (a is Map && b is Map)
      return a.length == b.length &&
          a.keys.every((k) => b.containsKey(k) && _equal(a[k], b[k]));
    return a == b;
  }
}

class DeviceSessionException implements Exception {
  final String code;
  const DeviceSessionException(this.code);
}

/// Runs before normal CLI initialization: no banners, prompts or debug logging.
Future<int> runPubAuth({String? settingsPath}) async {
  try {
    var size = 0;
    final bytes = <int>[];
    await for (final chunk in stdin) {
      size += chunk.length;
      if (size > 65536) throw const FormatException('Request too large');
      bytes.addAll(chunk);
    }
    final request = jsonDecode(utf8.decode(bytes));
    if (request is! Map<String, dynamic> ||
        request['protocolVersion'] != 1 ||
        request['interactive'] != false ||
        request['repository-url'] is! String)
      throw const FormatException('Invalid helper request');
    final session = await DeviceSession.load(
        settingsPath == null
            ? OnePubSettings.use()
            : OnePubSettings(pathToSettings: settingsPath),
        Uri.parse(request['repository-url'] as String));
    if (session == null) throw const DeviceSessionException('sign_in_required');
    final result = switch (request['action']) {
      'acquire' => await session.acquire(request),
      'prove' => await session.prove(request),
      _ => throw const FormatException('Unknown action'),
    };
    stdout.writeln(jsonEncode(result));
    return 0;
  } on Object {
    stdout.writeln(jsonEncode({
      'error': 'sign_in_required',
      'message': 'Run onepub login, then retry.'
    }));
    return 1;
  }
}
