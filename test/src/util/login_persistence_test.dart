import 'dart:convert';
import 'dart:io';

import 'package:onepub/src/onepub_settings.dart';
import 'package:onepub/src/util/login_persistence.dart';
import 'package:onepub/src/util/one_pub_token_store.dart';
import 'package:test/test.dart';

import 'login_preferences_test.dart' show completed;

void main() {
  late Directory directory;
  late OnePubSettings settings;
  late File tokens;
  late LoginPersistence persistence;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('onepub-save-');
    settings = OnePubSettings(pathToSettings: '${directory.path}/onepub.yaml')
      ..onepubUrl = 'http://localhost:58080'
      ..obfuscatedOrganisationId = 'old-org'
      ..organisationName = 'Old organisation'
      ..operatorEmail = 'old@example.test';
    await settings.save();
    tokens = File('${directory.path}/tokens/pub-tokens.json');
    await tokens.parent.create();
    await tokens.writeAsString(jsonEncode({
      'version': 1,
      'hosted': [
        {'url': 'http://localhost:58080/api/old-org/', 'token': 'old-token'},
        {'url': 'http://localhost:58081/api/other/', 'token': 'other-token'},
      ],
      'futureField': 'preserved',
    }));
    persistence = LoginPersistence(settings);
  });
  tearDown(() => directory.delete(recursive: true));

  test('recovery refreshes account details already loaded by this process',
      () async {
    final account = File(settings.pathToSettings);
    final oldAccount = await account.readAsBytes();
    final oldTokens = await tokens.readAsBytes();
    settings.obfuscatedOrganisationId = 'partial-new-org';
    await settings.save();
    await File('${tokens.parent.path}/onepub-login-recovery.json')
        .writeAsString(jsonEncode({
      'version': 1,
      'destinations': {
        'tokens': tokens.absolute.path,
        'account': account.absolute.path,
        'routing': persistence.preferences.file.absolute.path
      },
      'previous': {
        'tokens': base64Encode(oldTokens),
        'account': base64Encode(oldAccount),
        'routing': null
      },
    }));
    await OnePubTokenStore.withPathTo(tokens.parent.path, () async {
      await persistence.recover();
      expect(settings.obfuscatedOrganisationId, 'old-org');
      expect(settings.onepubApiUrl.path, '/api/old-org/');
    });
  });

  test('only one login can run per server and the lock is released on failure',
      () async {
    await OnePubTokenStore.withPathTo(tokens.parent.path, () async {
      await persistence.withLogin(() async {
        await expectLater(persistence.withLogin(() async {}), throwsStateError);
        final otherSettings =
            OnePubSettings(pathToSettings: settings.pathToSettings)
              ..onepubUrl = 'http://localhost:58081';
        await LoginPersistence(otherSettings).withLogin(() async {});
      });
      await expectLater(persistence.withLogin<void>(() {
        throw StateError('cancelled');
      }), throwsStateError);
      await persistence.withLogin(() async {});
    });
  });

  test('save replaces this server login and preserves other server credentials',
      () async {
    await OnePubTokenStore.withPathTo(tokens.parent.path, () async {
      await persistence.save(completed());
      expect(settings.obfuscatedOrganisationId, 'org-123');
      final stored = OnePubSettings(pathToSettings: settings.pathToSettings);
      expect(stored.obfuscatedOrganisationId, 'org-123');
      final Object? decoded = jsonDecode(await tokens.readAsString());
      expect(decoded, {
        'version': 1,
        'hosted': [
          {'url': 'http://localhost:58081/api/other/', 'token': 'other-token'},
          {
            'url': 'http://localhost:58080/api/org-123/',
            'token': 'not-a-real-token'
          },
        ],
        'futureField': 'preserved',
      });
      expect(
          (await persistence.preferences.load(persistence.server))
              ?.organisationCode,
          'acme');
    });
  });

  test('invalid token store leaves account and routing unchanged', () async {
    await tokens.writeAsString('invalid JSON');
    await OnePubTokenStore.withPathTo(tokens.parent.path, () async {
      await expectLater(persistence.save(completed()), throwsFormatException);
      expect(settings.obfuscatedOrganisationId, 'old-org');
      expect(
          OnePubSettings(pathToSettings: settings.pathToSettings)
              .obfuscatedOrganisationId,
          'old-org');
      expect(await tokens.readAsString(), 'invalid JSON');
      expect(persistence.preferences.file.existsSync(), isFalse);
    });
  });

  test('invalid routing file preserves previous credentials and account',
      () async {
    final before = await tokens.readAsString();
    await persistence.preferences.file.writeAsString('invalid JSON');
    await OnePubTokenStore.withPathTo(tokens.parent.path, () async {
      await expectLater(persistence.save(completed()), throwsFormatException);
      expect(await tokens.readAsString(), before);
      expect(settings.obfuscatedOrganisationId, 'old-org');
      expect(
          OnePubSettings(pathToSettings: settings.pathToSettings)
              .obfuscatedOrganisationId,
          'old-org');
    });
  });
}
