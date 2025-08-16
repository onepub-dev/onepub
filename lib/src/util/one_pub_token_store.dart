/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'package:dcli_core/dcli_core.dart';
import 'package:scope/scope.dart';

import '../onepub_settings.dart';
import '../token_store/credential.dart';
import '../token_store/hosted.dart';
import '../token_store/io.dart';
import '../token_store/token_store.dart';

class OnePubTokenStore {
  // Adds a OnePub Token into the pub.dev token store.
  //
  Future<void> addToken({
    required String onepubApiUrl,
    required String onepubToken,
  }) async {
    final normalisedUrl = validateAndNormalizeHostedUrl(onepubApiUrl);
    await clearOldTokens(normalisedUrl);
    await tokenStore
        .addCredential(Credential.token(normalisedUrl, onepubToken));
  }

// True if we have a onepub token for the given [onepubApiUrl]
  Future<bool> isLoggedIn(Uri onepubApiUrl) async =>
      (await tokenStore.findCredential(onepubApiUrl)) != null;

  /// throws [StateError] if called when not logged in.
  /// returns the onepubToken.
  Future<String> load() async {
    final settings = OnePubSettings.use();
    final credentials = await tokenStore.findCredential(settings.onepubApiUrl);

    if (credentials == null || credentials.token == null) {
      throw StateError('You may not call fetch when not logged in');
    }

    return credentials.token!;
  }

  Future<Iterable<Credential>> get credentials => tokenStore.credentials;

  /// Removes any onepub token from the pub token store
  /// for the given Url
  Future<void> clearOldTokens(Uri onepubApiUrl) async {
    await tokenStore.removeMatchingCredential(onepubApiUrl);
  }

  TokenStore get tokenStore => TokenStore(pathToTokenStore);

  // Used to inject an alternate location for the token store
  //
  static const scopeKey = ScopeKey<String>('PathToTokenStore');

  /// If no path has been injected we fall back to the default
  /// [dartConfigDir]
  static String get pathToTokenStore =>
      Scope.use(scopeKey, withDefault: () => dartConfigDir ?? '.');

  static Future<void> withPathTo(
      String pathToAlternateLocation, Future<void> Function() action) async {
    if (!exists(pathToAlternateLocation)) {
      createDir(pathToAlternateLocation, recursive: true);
    }
    final scope = Scope()..value(scopeKey, pathToAlternateLocation);
    await scope.run(action);
  }

  // returns the token for the given [onepubApiUrl]
  // if it is stored.
  Future<String?> getToken(String onepubApiUrl) async {
    final url = Uri.parse(onepubApiUrl);
    final credential = await tokenStore.findCredential(url);
    if (credential != null) {
      return credential.token;
    }
    return null;
  }
}
