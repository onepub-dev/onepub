/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'package:dcli/dcli.dart';
import '../onepub_settings.dart';

import '../token_store/credential.dart';
import '../token_store/hosted.dart';
import '../token_store/io.dart';
import '../token_store/token_store.dart';

class OnePubTokenStore {
  static const onepubSecretEnvKey = 'ONEPUB_TOKEN';

  void save(
      {required String onepubToken,
      required String obfuscatedOrganisationId,
      required String organisationName,
      required String operatorEmail}) {
    withEnvironment(() {
      final settings = OnePubSettings.use
        ..obfuscatedOrganisationId = obfuscatedOrganisationId
        ..organisationName = organisationName
        ..operatorEmail = operatorEmail
        ..save();
      clearOldTokens();
      tokenStore.addCredential(Credential.token(
          settings.onepubHostedUrl(obfuscatedOrganisationId), onepubToken));
    }, environment: {onepubSecretEnvKey: onepubToken});
  }

// True if we have a onepub token.
  bool get isLoggedIn {
    final settings = OnePubSettings.use;
    return tokenStore.findCredential(
            settings.onepubHostedUrl(settings.obfuscatedOrganisationId)) !=
        null;
  }

  /// throws [StateError] if called when not logged in.
  /// returns the onepubToken.
  String load() {
    final settings = OnePubSettings.use;
    final credentials = tokenStore.findCredential(
        settings.onepubHostedUrl(settings.obfuscatedOrganisationId));

    if (credentials == null || credentials.token == null) {
      throw StateError('You may not call fetch when not logged in');
    }

    return credentials.token!;
  }

  Iterable<Credential> get credentials => tokenStore.credentials;

  /// Removes the onepub token from the pub token store.
  void clearOldTokens() {
    final settings = OnePubSettings.use;
    tokenStore.removeMatchingCredential(
        validateAndNormalizeHostedUrl(settings.onepubApiUrl));
    // tokenStore
    //  .removeCredential(_hostedUrl(OnePubSettings.use
    // .obfuscatedOrganisationId));
  }

  TokenStore get tokenStore => TokenStore(dartConfigDir);
}
