import 'dart:io';

import 'package:onepub/src/token_store/credential.dart';
import 'package:onepub/src/util/one_pub_token_store.dart';
import 'package:test/test.dart';

import '../../../tool/trusted_publishing_e2e.dart';
import '../../test_settings.dart';

final _localUrl = Uri.parse(assertSafeOnePubTestUrl('http://localhost:8080'));
final _pubDevUrl = Uri.parse('https://pub.dev');

void main() {
  test('finds the new credential with an existing pub.dev env credential', () {
    final before = [Credential.env(_pubDevUrl, 'PUB_TOKEN')];
    const token = 'new-local-token-that-must-not-be-logged';
    final after = [...before, Credential.token(_localUrl, token)];

    final installed = newlyInstalledCredential(before, after);

    expect(installed.url, _localUrl);
    expect(installed.token, token);
  });

  test('finds one credential when the baseline is empty', () {
    final credential = Credential.token(_localUrl, 'new-token');

    expect(newlyInstalledCredential([], [credential]), same(credential));
  });

  test('rejects a login that installs no new credential', () {
    final existing = Credential.token(_pubDevUrl, 'existing-token');

    _expectStateError(
      () => newlyInstalledCredential([existing], [existing]),
      contains('Expected one newly installed publishing credential.'),
    );
  });

  test('rejects a login that installs multiple new credentials', () {
    final existing = Credential.token(_pubDevUrl, 'existing-token');
    final first = Credential.token(
      Uri.parse('http://localhost:8080/first'),
      'first-new-token',
    );
    final second = Credential.token(
      Uri.parse('http://localhost:8080/second'),
      'second-new-token',
    );

    _expectStateError(
      () => newlyInstalledCredential(
        [existing],
        [existing, first, second],
      ),
      contains('Expected one newly installed publishing credential.'),
    );
  });

  test('rejects a login that changes an existing credential', () {
    final before = [Credential.token(_pubDevUrl, 'old-existing-token')];
    final after = [Credential.token(_pubDevUrl, 'changed-existing-token')];

    _expectStateError(
      () => newlyInstalledCredential(before, after),
      contains('Trusted login changed an existing credential.'),
    );
  });

  test('rejects a login that removes an existing credential', () {
    final before = [Credential.token(_pubDevUrl, 'existing-token')];

    _expectStateError(
      () => newlyInstalledCredential(before, []),
      contains('Trusted login changed an existing credential.'),
    );
  });

  test('rejects duplicate credentials in the result', () {
    final duplicate = Credential.token(_pubDevUrl, 'duplicate-token');

    _expectStateError(
      () => newlyInstalledCredential(
        [duplicate],
        [duplicate, duplicate],
      ),
      contains('Duplicate publishing credentials found.'),
    );
  });

  test('rejects a newly installed environment-only credential', () {
    final existing = Credential.token(_pubDevUrl, 'existing-token');
    final environmentCredential = Credential.env(_localUrl, 'LOCAL_TOKEN');

    _expectStateError(
      () => newlyInstalledCredential(
        [existing],
        [existing, environmentCredential],
      ),
      contains('Expected one newly installed publishing credential.'),
    );
  });

  test('does not include token values in helper errors', () {
    const oldToken = 'old-secret-token-must-not-leak';
    const changedToken = 'changed-secret-token-must-not-leak';
    final before = [Credential.token(_pubDevUrl, oldToken)];
    final after = [Credential.token(_pubDevUrl, changedToken)];

    expect(
      () => newlyInstalledCredential(before, after),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'error',
          allOf(
            isNot(contains(oldToken)),
            isNot(contains(changedToken)),
          ),
        ),
      ),
    );
  });

  test('finds a credential after a real TokenStore add/read round-trip',
      () async {
    final temp = Directory.systemTemp.createTempSync('trusted-credential-');
    addTearDown(() => temp.deleteSync(recursive: true));

    await OnePubTokenStore.withPathTo(temp.path, () async {
      final store = OnePubTokenStore();
      await store.tokenStore
          .addCredential(Credential.env(_pubDevUrl, 'PUB_TOKEN'));
      final before = (await store.credentials).toList();
      await store.addToken(
        onepubApiUrl: _localUrl.toString(),
        onepubToken: 'round-trip-token',
      );
      final after = (await store.credentials).toList();

      final installed = newlyInstalledCredential(before, after);
      expect(installed.url, _localUrl);
      expect(installed.token, 'round-trip-token');
      expect(after, hasLength(2));
    });
  });
}

void _expectStateError(
  void Function() action,
  Matcher message,
) {
  expect(
    action,
    throwsA(
      isA<StateError>().having(
        (error) => error.message,
        'message',
        message,
      ),
    ),
  );
}
