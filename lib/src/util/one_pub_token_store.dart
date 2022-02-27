import 'package:dcli/dcli.dart';
import '../onepub_settings.dart';

import '../token_store/credential.dart';
import '../token_store/hosted.dart';
import '../token_store/io.dart';
import '../token_store/token_store.dart';

class OnePubTokenStore {
  static const onepubSecretEnvKey = 'ONEPUB_SECRET';

  void save(String onepubToken) {
    withEnvironment(() {
      tokenStore.addCredential(Credential.token(_hostedUrl, onepubToken));
    }, environment: {onepubSecretEnvKey: onepubToken});
  }

// True if we have a onepub token.
  bool get isLoggedIn => tokenStore.findCredential(_hostedUrl) != null;

  /// throws [StateError] if called when not logged in.
  /// returns the onepubToken.
  String fetch() {
    final credentials = tokenStore.findCredential(_hostedUrl);

    if (credentials == null || credentials.token == null) {
      throw StateError('You may not call fetch when not logged in');
    }

    return credentials.token!;
  }

  /// Removes the onepub token from the pub token store.
  void remove() {
    tokenStore.removeCredential(_hostedUrl);
  }

  TokenStore get tokenStore => TokenStore(dartConfigDir);

  Uri get _hostedUrl =>
      validateAndNormalizeHostedUrl(OnePubSettings().onepubWebUrl);
}
