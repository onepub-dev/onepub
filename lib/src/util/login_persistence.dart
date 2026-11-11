import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import '../api/auth_response.dart';
import '../onepub_settings.dart';
import 'login_file_transaction.dart';
import 'login_preferences.dart';
import 'one_pub_token_store.dart';

/// Commits a verified login without discarding the previous usable login first.
class LoginPersistence {
  final OnePubSettings settings;

  LoginPersistence(this.settings);

  LoginPreferences get preferences => LoginPreferences(
      path.join(path.dirname(settings.pathToSettings), 'login-routing.json'));

  Uri get server => Uri.parse(settings.resolveApiEndPoint(''));

  File get _tokens =>
      File(path.join(OnePubTokenStore.pathToTokenStore, 'pub-tokens.json'));

  LoginFileTransaction get _transaction => LoginFileTransaction(
          File(path.join(
              OnePubTokenStore.pathToTokenStore, 'onepub-login-recovery.json')),
          {
            'tokens': _tokens,
            'account': File(settings.pathToSettings),
            'routing': preferences.file
          });

  Future<void> recover() async {
    await _transaction.locked(() async {});
    settings.reload();
  }

  /// Keep at most one browser login active for a server on this device.
  Future<T> withLogin<T>(Future<T> Function() action) {
    final key = const Uuid()
        .v5(Namespace.url.value, LoginPreferences.serverKey(server));
    return LoginFileTransaction(
        File(path.join(OnePubTokenStore.pathToTokenStore, 'onepub-login-$key')),
        const {}).locked(action);
  }

  Future<void> save(AuthResponse result) async {
    if (result.status != AwaitLoginStatus.authSucceeded) {
      throw StateError('Only a completed login can be saved.');
    }
    final tokens = _tokens;
    final transaction = _transaction;
    await transaction.locked(() async {
      final current = OnePubSettings(pathToSettings: settings.pathToSettings);
      final tokenContents = await _tokenContents(tokens, server, result);
      await transaction.commit({
        'tokens': tokenContents,
        'account': current.loginContents(
            organisationId: result.obfuscatedOrganisationId,
            organisationName: result.organisationName,
            operatorEmail: result.operatorEmail),
        'routing': await preferences.contentsFor(server, result),
      });
    });
    settings
      ..obfuscatedOrganisationId = result.obfuscatedOrganisationId
      ..organisationName = result.organisationName
      ..operatorEmail = result.operatorEmail;
  }

  static Future<String> _tokenContents(
      File file, Uri server, AuthResponse result) async {
    final Object? decoded = file.existsSync()
        ? jsonDecode(await file.readAsString())
        : <String, Object?>{'version': 1, 'hosted': <Object?>[]};
    if (decoded is! Map<String, dynamic> ||
        decoded['version'] != 1 ||
        decoded['hosted'] is! List) {
      throw const FormatException('Cannot update an invalid pub token store.');
    }
    final hosted = <Object?>[];
    final prefix = '${server.path.replaceFirst(RegExp(r'/+$'), '')}/';
    for (final Object? entry in decoded['hosted'] as List) {
      if (entry is! Map<String, dynamic> || entry['url'] is! String) {
        throw const FormatException('Cannot update an invalid pub credential.');
      }
      final uri = Uri.parse(entry['url'] as String);
      final sameServer = uri.scheme == server.scheme &&
          uri.host == server.host &&
          uri.port == server.port &&
          uri.path.startsWith(prefix);
      if (!sameServer) {
        hosted.add(entry);
      }
    }
    hosted.add({
      'url': server
          .replace(path: '$prefix${result.obfuscatedOrganisationId}/')
          .toString(),
      'token': result.onepubToken
    });
    return jsonEncode({...decoded, 'hosted': hosted});
  }
}
