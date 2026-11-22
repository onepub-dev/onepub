import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import '../api/auth_response.dart';
import '../device/device_session.dart';
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
            'routing': preferences.file,
            'devices': DeviceSession.registry(settings)
          });

  Future<void> recover() async {
    // Finish journals written by pre-device clients with their original set
    // of fixed destinations before enabling the extended transaction.
    final transaction = _transaction;
    if (await transaction.journal.exists()) {
      final value = jsonDecode(await transaction.journal.readAsString());
      if (value is Map<String, dynamic> &&
          value['destinations'] is Map &&
          !(value['destinations'] as Map).containsKey('devices')) {
        await LoginFileTransaction(transaction.journal,
                Map.of(transaction.destinations)..remove('devices'))
            .locked(() async {});
      }
    }
    await transaction.locked(() async {});
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

  Future<void> save(AuthResponse result, {Directory? deviceStorage}) async {
    if (result.status != AwaitLoginStatus.authSucceeded) {
      throw StateError('Only a completed login can be saved.');
    }
    final tokens = _tokens;
    final transaction = _transaction;
    await transaction.locked(() async {
      final current = OnePubSettings(pathToSettings: settings.pathToSettings);
      final enrollment = result.deviceEnrollment;
      DeviceSession? session;
      if (enrollment != null) {
        if (deviceStorage == null ||
            enrollment['deviceId'] is! String ||
            enrollment['repositoryUrl'] is! String) {
          throw const FormatException('Invalid device enrollment');
        }
        final repository = Uri.parse(enrollment['repositoryUrl'] as String);
        final expected = server.replace(
            path:
                '${server.path.replaceFirst(RegExp(r'/+$'), '')}/${result.obfuscatedOrganisationId}/');
        if (repository != expected)
          throw const FormatException('Enrollment repository mismatch');
        DeviceSession.validateRepository(repository);
        session = DeviceSession(
            repository, enrollment['deviceId'] as String, deviceStorage);
      }
      final tokenContents = await _tokenContents(tokens, server, result,
          device: session != null, settingsFile: settings.pathToSettings);
      final devices = await DeviceSession.readRegistry(settings);
      if (session != null) {
        devices[session.repository.toString()] = session.metadata;
      } else {
        final path = server.path.replaceFirst(RegExp(r'/+$'), '');
        devices.remove(server
            .replace(path: '$path/${result.obfuscatedOrganisationId}/')
            .toString());
      }
      await transaction.commit({
        'tokens': tokenContents,
        'devices': jsonEncode(devices),
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

  static List<String> helperCommand({String? settingsFile}) {
    // Native executables invoke themselves. Dart snapshots retain their exact
    // installed entry point rather than resolving an unrelated PATH command.
    final suffix = [
      '_pub-auth',
      if (settingsFile != null) ...[
        '--settings',
        File(settingsFile).absolute.path
      ]
    ];
    final script = Platform.script;
    if (script.scheme == 'file' &&
        (script.path.endsWith('.dart') || script.path.endsWith('.snapshot'))) {
      return [Platform.resolvedExecutable, script.toFilePath(), ...suffix];
    }
    return [Platform.resolvedExecutable, ...suffix];
  }

  static Future<String> _tokenContents(
      File file, Uri server, AuthResponse result,
      {bool device = false, String? settingsFile}) async {
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
      final sameRepository =
          uri.path == '$prefix${result.obfuscatedOrganisationId}/';
      if (!sameServer ||
          ((device || entry.containsKey('authHelper')) && !sameRepository)) {
        hosted.add(entry);
      }
    }
    hosted.add({
      'url': server
          .replace(path: '$prefix${result.obfuscatedOrganisationId}/')
          .toString(),
      if (!device) 'token': result.onepubToken,
      if (device) 'authHelper': helperCommand(settingsFile: settingsFile)
    });
    return jsonEncode({...decoded, 'hosted': hosted});
  }
}
