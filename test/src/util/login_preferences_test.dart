import 'dart:convert';
import 'dart:io';

import 'package:onepub/src/api/auth_response.dart';
import 'package:onepub/src/util/login_preferences.dart';
import 'package:onepub/src/util/send_command.dart';
import 'package:test/test.dart';

AuthResponse completed({bool sso = true}) =>
    AuthResponse.parse(EndpointResponse(
      200,
      StringBuffer(jsonEncode({
        'body': {
          'status': 'authSucceeded',
          'onePubToken': 'not-a-real-token',
          'firstLogin': false,
          'operatorEmail': 'member@example.test',
          'organisationName': 'Example',
          'obfuscatedOrganisationId': 'org-123',
          if (sso)
            'loginRouting': {
              'method': 'sso',
              'organisationCode': 'acme',
              'organisationId': 'org-123',
            },
        },
      })),
      CommandType.cli,
    ));

void main() {
  late Directory directory;
  late LoginPreferences preferences;
  final first = Uri.parse('http://localhost:58080/api');
  final second = Uri.parse('http://localhost:58081/api');

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('onepub-login-prefs-');
    preferences = LoginPreferences('${directory.path}/login.json');
  });
  tearDown(() => directory.delete(recursive: true));

  test('preferences are isolated by server and contain no credential',
      () async {
    await preferences.save(first, completed());
    expect((await preferences.load(first))?.organisationCode, 'acme');
    expect(await preferences.load(second), isNull);
    expect((await preferences.load(Uri.parse('$first/')))?.method, 'sso');
    final data = await preferences.file.readAsString();
    expect(data, isNot(contains('not-a-real-token')));
    expect(data, isNot(contains('member@example.test')));
  });

  test('ordinary success replaces SSO without affecting another server',
      () async {
    await preferences.save(first, completed());
    await preferences.save(second, completed());
    await preferences.save(first, completed(sso: false));
    expect((await preferences.load(first))?.method, 'ordinary');
    expect((await preferences.load(first))?.organisationCode, isNull);
    expect((await preferences.load(second))?.method, 'sso');
    await preferences.forget(first);
    expect(await preferences.load(first), isNull);
    expect((await preferences.load(second))?.method, 'sso');
  });

  test('malformed state routes to chooser and is not silently overwritten',
      () async {
    await preferences.file.writeAsString('invalid json');
    expect(await preferences.load(first), isNull);
    await expectLater(
        preferences.save(first, completed()), throwsFormatException);
    expect(await preferences.file.readAsString(), 'invalid json');
  });

  test('unsuccessful authentication cannot alter remembered routing', () async {
    await preferences.save(first, completed());
    final retry = AuthResponse.parse(EndpointResponse(
        200,
        StringBuffer('{"body":{"status":"retry","pollInterval":3}}'),
        CommandType.cli));
    await expectLater(preferences.save(first, retry), throwsStateError);
    expect((await preferences.load(first))?.method, 'sso');
  });
}
