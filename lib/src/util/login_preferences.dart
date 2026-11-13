import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../api/auth_response.dart';
import '../exceptions.dart';

/// Device-local routing preferences without tokens or authentication proof.
class LoginPreferences {
  final File file;

  LoginPreferences(String path) : file = File(path);

  static String serverKey(Uri server) {
    if (!server.hasScheme ||
        server.host.isEmpty ||
        server.userInfo.isNotEmpty ||
        server.hasQuery ||
        server.hasFragment) {
      throw ArgumentError('A server URL without credentials is required.');
    }
    final path = server.path.replaceFirst(RegExp(r'/+$'), '');
    return server.replace(path: path).toString();
  }

  Future<Map<String, Object?>> _read() async {
    if (!file.existsSync()) {
      return {};
    }
    final Object? data = jsonDecode(await file.readAsString());
    if (data is! Map<String, dynamic> ||
        data['version'] != 1 ||
        data['servers'] is! Map<String, dynamic>) {
      throw const FormatException('Invalid login preferences');
    }
    return Map<String, Object?>.from(data['servers'] as Map<String, dynamic>);
  }

  /// Invalid convenience state falls back to the chooser, never another tenant.
  Future<VerifiedLoginRouting?> load(Uri server) async {
    try {
      final value = (await _read())[serverKey(server)];
      if (value is! Map<String, dynamic>) {
        return null;
      }
      final id = value['organisationId'];
      if (id is! String) {
        return null;
      }
      return VerifiedLoginRouting.parse(value, id);
    } on FormatException {
      return null;
    } on APIException {
      return null;
    }
  }

  /// Call inside the login persistence transaction, after verified completion.
  Future<void> save(Uri server, AuthResponse result) async {
    await _write(await contentsFor(server, result));
  }

  /// Produces the next file without modifying the current login.
  Future<String> contentsFor(Uri server, AuthResponse result) async {
    if (result.status != AwaitLoginStatus.authSucceeded) {
      throw StateError('Only a successful login can update preferences.');
    }
    final routing = result.loginRouting;
    final servers = await _read();
    servers[serverKey(server)] = <String, Object?>{
      'method': routing?.method ?? 'ordinary',
      'organisationId': result.obfuscatedOrganisationId,
      if (routing?.method == 'sso')
        'organisationCode': routing!.organisationCode,
    };
    return jsonEncode({'version': 1, 'servers': servers});
  }

  Future<void> forget(Uri server) async {
    final servers = await _read();
    servers.remove(serverKey(server));
    await _write(jsonEncode({'version': 1, 'servers': servers}));
  }

  Future<void> _write(String contents) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.${const Uuid().v4()}.tmp');
    try {
      await temporary.writeAsString(contents, flush: true);
      await temporary.rename(file.path);
    } finally {
      if (temporary.existsSync()) {
        await temporary.delete();
      }
    }
  }
}
