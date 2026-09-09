import 'dart:io';

import 'package:dcli/dcli.dart' as dcli;
import 'package:dcli_core/dcli_core.dart' as core;
import 'package:onepub/src/api/api.dart';
import 'package:onepub/src/api/onepub_token.dart';
import 'package:onepub/src/onepub_settings.dart';
import 'package:onepub/src/util/one_pub_token_store.dart';
import 'package:path/path.dart';
import 'package:settings_yaml/settings_yaml.dart';

const _explicitSafeOnePubTestHosts = <String>{
  'beta.onepub.dev',
  'staging.onepub.dev',
  'squarephone.biz',
  'localhost',
  '127.0.0.1',
  '::1',
  'host.docker.internal',
};

class TestSettings {
  late final SettingsYaml _settings;

  TestSettings() {
    _settings = SettingsYaml.load(pathToSettings: pathToTestSettings);
  }

  String get onepubUrl => _settings.asString('onepubUrl');

  set onepubUrl(String url) => _settings['onepubUrl'] = url;

  Future<void> save() => _settings.save();

  String get organisationId => _settings.asString('organisationId');

  set organisationId(String value) => _settings['organisationId'] = value;

  String get organisationName => _settings.asString('organisationName');

  String get member => _settings.asString('member');

  String get onepubToken => _settings.asString('onepub_token');

  String get pathToTestSettings {
    final pathToTest = dcli.DartProject.self.pathToTestDir;

    return join(pathToTest, 'test_settings.yaml');
  }

  static String resolveOnePubUrl({String? override}) {
    final envUrl = dcli.env['ONEPUB_STAGING_URL'];
    final resolved = (() {
      if (override != null && override.isNotEmpty) {
        return override;
      }
      if (envUrl != null && envUrl.isNotEmpty) {
        return envUrl;
      }
      return TestSettings().onepubUrl;
    })();

    return assertSafeOnePubTestUrl(
      resolved,
      source: 'TestSettings.resolveOnePubUrl',
    );
  }
}

String assertSafeOnePubTestUrl(String url, {String source = 'test settings'}) {
  late final Uri uri;
  try {
    uri = Uri.parse(url);
  } on FormatException catch (e) {
    throw StateError('Invalid OnePub test URL from $source: $url ($e)');
  }

  final host = uri.host.toLowerCase();
  final scheme = uri.scheme.toLowerCase();
  if (host.isEmpty || (scheme != 'http' && scheme != 'https')) {
    throw StateError(
      'Invalid OnePub test URL from $source: $url. '
      'Expected an absolute http(s) URL.',
    );
  }

  if (!_isSafeOnePubTestHost(host)) {
    throw StateError(
      'OnePub integration tests must never run against production '
      'https://onepub.dev. $source resolved to $url.',
    );
  }

  return url;
}

bool _isSafeOnePubTestHost(String host) {
  if (_explicitSafeOnePubTestHosts.contains(host)) {
    return true;
  }
  if (host.endsWith('.local')) {
    return true;
  }
  return _isPrivateIpv4Host(host);
}

bool _isPrivateIpv4Host(String host) {
  final parts = host.split('.');
  if (parts.length != 4) {
    return false;
  }
  final octets = <int>[];
  for (final part in parts) {
    final value = int.tryParse(part);
    if (value == null || value < 0 || value > 255) {
      return false;
    }
    octets.add(value);
  }

  if (octets[0] == 10) {
    return true;
  }
  if (octets[0] == 192 && octets[1] == 168) {
    return true;
  }
  if (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) {
    return true;
  }
  return false;
}

Future<T> withTestServer<T>(
  Future<T> Function() action, {
  String? onepubUrlOverride,
  bool resolveOrganisationToken = true,
}) {
  final testSettings = TestSettings();
  return core.withTempDirAsync(
      (tempSettingsDir) => OnePubSettings.withPathTo(tempSettingsDir, () async {
            final settings = OnePubSettings.use()
              ..operatorEmail = testSettings.member
              ..organisationName = testSettings.organisationName
              ..obfuscatedOrganisationId = testSettings.organisationId
              ..onepubUrl = TestSettings.resolveOnePubUrl(
                override: onepubUrlOverride,
              );
            await settings.save();

            late T result;
            await OnePubTokenStore.withPathTo(tempSettingsDir, () async {
              await OnePubTokenStore().addToken(
                onepubApiUrl: settings.onepubApiUrlAsString,
                onepubToken: testSettings.onepubToken,
              );
              if (resolveOrganisationToken) {
                final onepubToken = await _resolveTestServerToken(
                  testSettings: testSettings,
                );
                if (onepubToken != testSettings.onepubToken) {
                  await OnePubTokenStore().addToken(
                    onepubApiUrl: settings.onepubApiUrlAsString,
                    onepubToken: onepubToken,
                  );
                }
              }
              result = await action();
            });

            return result;
          }));
}

Future<String> _resolveTestServerToken({
  required TestSettings testSettings,
}) async {
  final token = await OnePubTokenStore().load();
  final response = await API().fetchMember(token);
  if (response.success) {
    final member = response.toMember();
    if (member.obfuscatedOrganisationId == testSettings.organisationId) {
      return token;
    }
  }

  final cachedToken = await _loadCachedOrganisationToken(
    testSettings: testSettings,
    sourceToken: token,
  );
  if (cachedToken != null) {
    return cachedToken;
  }

  final tokenResponse = await _exportTestMemberTokenWithRetry(
    testSettings: testSettings,
  );
  if (!tokenResponse.success || tokenResponse.token == null) {
    throw StateError(
      'Unable to obtain a test token for ${testSettings.member} in '
      '${testSettings.organisationId}. ${tokenResponse.errorMessage}',
    );
  }
  await _writeCachedOrganisationToken(
    testSettings: testSettings,
    sourceToken: token,
    organisationToken: tokenResponse.token!,
  );
  return tokenResponse.token!;
}

Future<OnePubToken> _exportTestMemberTokenWithRetry({
  required TestSettings testSettings,
}) async {
  const maxAttempts = 5;
  OnePubToken? lastResponse;
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    final response = await API().exportTestMemberToken(
      obfuscatedOrganisationId: testSettings.organisationId,
      memberEmail: testSettings.member,
    );
    if (response.success) {
      return response;
    }
    lastResponse = response;
    if (!_isRateLimitMessage(response.errorMessage) || attempt == maxAttempts) {
      return response;
    }

    final delay = Duration(seconds: attempt * 2);
    stderr.writeln(
      'Test token exchange hit rate limit on attempt $attempt/$maxAttempts; '
      'retrying in ${delay.inSeconds}s.',
    );
    await Future<void>.delayed(delay);
  }
  return lastResponse!;
}

bool _isRateLimitMessage(String? message) {
  final normalized = (message ?? '').toLowerCase();
  return normalized.contains('too many cli requests') ||
      normalized.contains('too many requests') ||
      normalized.contains('rate limit');
}

Future<String?> _loadCachedOrganisationToken({
  required TestSettings testSettings,
  required String sourceToken,
}) async {
  final cacheFile = _organisationTokenCacheFile(
    testSettings: testSettings,
    sourceToken: sourceToken,
  );
  if (!cacheFile.existsSync()) {
    return null;
  }

  try {
    final cachedToken = cacheFile.readAsStringSync().trim();
    if (cachedToken.isEmpty) {
      return null;
    }
    final tokenResponse = await API().fetchMember(cachedToken);
    if (!tokenResponse.success) {
      return null;
    }
    final member = tokenResponse.toMember();
    if (member.email == testSettings.member &&
        member.obfuscatedOrganisationId == testSettings.organisationId) {
      return cachedToken;
    }
  } catch (_) {
    return null;
  }
  return null;
}

Future<void> _writeCachedOrganisationToken({
  required TestSettings testSettings,
  required String sourceToken,
  required String organisationToken,
}) async {
  final cacheFile = _organisationTokenCacheFile(
    testSettings: testSettings,
    sourceToken: sourceToken,
  );
  await cacheFile.parent.create(recursive: true);
  await cacheFile.writeAsString(organisationToken);
}

File _organisationTokenCacheFile({
  required TestSettings testSettings,
  required String sourceToken,
}) {
  final sourceTokenPrefix =
      sourceToken.length <= 16 ? sourceToken : sourceToken.substring(0, 16);
  final key = _safeCacheKey([
    testSettings.onepubUrl,
    testSettings.organisationId,
    testSettings.member,
    sourceTokenPrefix,
  ].join('_'));
  return File('${Directory.systemTemp.path}/onepub_test_token_cache/$key');
}

String _safeCacheKey(String input) {
  final buffer = StringBuffer();
  for (final codeUnit in input.codeUnits) {
    final isDigit = codeUnit >= 48 && codeUnit <= 57;
    final isUpper = codeUnit >= 65 && codeUnit <= 90;
    final isLower = codeUnit >= 97 && codeUnit <= 122;
    buffer.write(
        isDigit || isUpper || isLower ? String.fromCharCode(codeUnit) : '_');
  }
  return buffer.toString();
}

//   /// Updates the inscope OnePubSettings by overriding the current
//   /// settings with the details form this.
//   void applyToOnePubSettings(OnePubSettings onepubSettings) {
//     onepubSettings
//       ..operatorEmail = member
//       ..organisationName = organisationName
//       ..obfuscatedOrganisationId = organisationId
//       ..onepubUrl = onepubUrl;
//   }

//   OnePubSettings createOnePubSettings() => OnePubSettings()
//     ..operatorEmail = member
//     ..organisationName = organisationName
//     ..obfuscatedOrganisationId = organisationId
//     ..onepubUrl = onepubUrl;
// }

// /// Initialises a OnePubSettings file in a tmp directory
// /// copying its initial state from the test_settings.yaml file
// /// in the project 'test' directory.
// Future<void> withTestSettings(
//     Future<void> Function(TestSettings testSettings) action,
//     {bool forAuthentication = false}) async {
//   await core.withTempDir((tempSettingsDir) async {
//     // control the location of the onepub settings file.
//     final settings = OnePubSettings.use();
//     final testSettings = TestSettings();
//     testSettings.createOnePubSettings().saveTo(tempSettingsDir);

//     await OnePubSettings.withPathTo(tempSettingsDir, () async {
//       // set an alternate location for the token store
//       await OnePubTokenStore.withPathTo(tempSettingsDir, () async {
//         if (!forAuthentication) {
//           settings
//             ..operatorEmail = testSettings.member
//             ..organisationName = testSettings.organisationName
//             ..obfuscatedOrganisationId = testSettings.organisationId;
//         }
//         settings
//           ..onepubUrl = testSettings.onepubUrl
//           ..save();
//         OnePubTokenStore().addToken(
//             onepubApiUrl: settings.onepubApiUrlAsString,
//             onepubToken: testSettings.onepubToken);

//         await action(testSettings);
//       });
//     });
//   });
