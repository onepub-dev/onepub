/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'package:dcli/dcli.dart';
import 'package:scope/scope.dart';

import '../onepub_settings.dart';
import '../token_store/credential.dart';
import '../token_store/hosted.dart';
import '../token_store/io.dart';
import '../token_store/token_store.dart';

class OnePubTokenStore {
  // Adds a OnePub Token into the pub.dev token store.
  //
  void addToken({
    required String onepubApiUrl,
    required String onepubToken,
  }) {
    final normalisedUrl = validateAndNormalizeHostedUrl(onepubApiUrl);
    clearOldTokens(normalisedUrl);
    tokenStore.addCredential(Credential.token(normalisedUrl, onepubToken));
  }

// True if we have a onepub token for the given [onepubApiUrl]
  bool isLoggedIn(Uri onepubApiUrl) =>
      tokenStore.findCredential(onepubApiUrl) != null;

  /// throws [StateError] if called when not logged in.
  /// returns the onepubToken.
  String load() {
    final settings = OnePubSettings.use();
    final credentials = tokenStore.findCredential(settings.onepubApiUrl);

    if (credentials == null || credentials.token == null) {
      throw StateError('You may not call fetch when not logged in');
    }

    return credentials.token!;
  }

  Iterable<Credential> get credentials => tokenStore.credentials;

  /// Removes any onepub token from the pub token store
  /// for the given Url
  void clearOldTokens(Uri onepubApiUrl) {
    tokenStore.removeMatchingCredential(onepubApiUrl);
  }

  TokenStore get tokenStore => TokenStore(pathToTokenStore);

  // Used to inject an alternate location for the token store
  //
  static final scopeKey = ScopeKey<String>('PathToTokenStore');

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
  String? getToken(String onepubApiUrl) {
    final url = Uri.parse(onepubApiUrl);

    return getTokenByUri(url);
  }

  // returns the token for the given [onepubApiUrl]
  // if it is stored.
  String? getTokenByUri(Uri onepubApiUrl) {
    final credential = tokenStore.findCredential(onepubApiUrl);
    if (credential != null) {
      return credential.token;
    }
    return null;
  }
}
