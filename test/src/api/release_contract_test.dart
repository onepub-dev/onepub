import 'dart:convert';

import 'package:onepub/src/api/auth_response.dart';
import 'package:onepub/src/api/cli_models.dart';
import 'package:onepub/src/api/logout.dart';
import 'package:onepub/src/api/onepub_token.dart';
import 'package:onepub/src/api/organisation.dart';
import 'package:onepub/src/api/versions.dart';
import 'package:onepub/src/exceptions.dart';
import 'package:onepub/src/util/send_command.dart';
import 'package:test/test.dart';

import '../../test_settings.dart';

// Synthetic values using the field names and envelopes from onepub-vaadin
// tag 5.15.18: JsonStatus, JsonOrganisation, JsonCliAuthResponse,
// JsonExportToken, JsonSuccess, JsonVersions and JsonVersion.
EndpointResponse cli(Map<String, dynamic> json, {int status = 200}) =>
    EndpointResponse(status, StringBuffer(jsonEncode(json)), CommandType.cli);

Map<String, dynamic> loginBody() => {
      'status': 'authSucceeded',
      'onePubToken': 'test-token',
      'firstLogin': false,
      'operatorEmail': 'member@example.test',
      'organisationName': 'Test Org',
      'obfuscatedOrganisationId': 'test-org',
    };

void main() {
  test('5.15.18 status, organisation, export and logout contracts', () {
    final status = cli({
      'body': {'message': 'Status normal', 'version': '5.15.18'},
    }).requireCliBody(CliStatusBody.fromJson);
    expect(status.version, '5.15.18');
    final org = Organisation(cli({
      'body': {'organisationName': 'Test Org', 'obfuscatedId': 'test-org'},
    }));
    expect(org.success, isTrue);
    expect(org.obfuscatedId, 'test-org');
    expect(
        OnePubToken(cli({
          'body': {'onepubToken': 'test-token'}
        })).token,
        'test-token');
    expect(
        Logout(cli({
          'success': {'message': 'Logged out'}
        })).success,
        isTrue);
  });

  test('5.15.18 login success, retry, timeout and denial contracts', () {
    final auth = AuthResponse.parse(cli({'body': loginBody()}));
    expect(auth.onepubToken, 'test-token');
    expect(auth.obfuscatedOrganisationId, 'test-org');
    expect(auth.firstLogin, isFalse);
    expect(
        AuthResponse.parse(cli({
          'body': {'status': 'retry', 'pollInterval': 4}
        })).pollInterval,
        4);
    expect(
        () => AuthResponse.parse(cli({
              'body': {'status': 'timeout'}
            })),
        throwsA(isA<ExitException>()));
    expect(
      () => AuthResponse.parse(cli({
        'body': {'status': 'authFailed', 'message': 'Access denied'},
      }, status: 401)),
      throwsA(isA<ExitException>()
          .having((e) => e.message, 'message', contains('Access denied'))),
    );
  });

  test('rejects absent and invalid required organisation and token fields', () {
    for (final value in [null, '', ' ', 42]) {
      expect(
          () => Organisation(cli({
                'body': {
                  'organisationName': 'Test Org',
                  'obfuscatedId': value,
                }
              })),
          throwsA(isA<APIException>()));
      expect(
          () => OnePubToken(cli({
                'body': {'onepubToken': value}
              })),
          throwsA(isA<APIException>()));
    }
    for (final body in ['', '{"success":{"message":"OK"}}', '{"body":{}}']) {
      expect(
          () => Organisation(
              EndpointResponse(200, StringBuffer(body), CommandType.cli)),
          throwsA(isA<APIException>()));
    }
  });

  test('rejects incomplete successful login before credentials can be saved',
      () {
    for (final field in loginBody().keys) {
      final body = loginBody()..remove(field);
      expect(() => AuthResponse.parse(cli({'body': body})),
          throwsA(isA<APIException>()),
          reason: field);
    }
  });

  test('missing or zero retry interval cannot cause a tight polling loop', () {
    for (final interval in [null, 0, -1]) {
      expect(
          AuthResponse.parse(cli({
            'body': {
              'status': 'retry',
              'pollInterval': interval,
            }
          })).pollInterval,
          3);
    }
  });

  test('HTTP failures and error envelopes take precedence over body/success',
      () {
    for (final response in [
      cli({
        'body': {'organisationName': 'Test Org', 'obfuscatedId': 'test-org'}
      }, status: 500),
      cli({
        'success': {'message': 'OK'},
        'error': {'message': 'Denied'}
      }),
    ]) {
      expect(response.success, isFalse);
      expect(response.parseCli(CliOrganisationBody.fromJson).error, isNotNull);
    }
  });

  test('5.15.18 package metadata preserves retraction and archive details', () {
    final archive =
        '${assertSafeOnePubTestUrl('http://localhost:8080')}/archive';
    final version = {
      'version': '1.0.0',
      'retracted': true,
      'archive_url': archive,
      'pubspec': {'name': 'test_package', 'version': '1.0.0'},
    };
    final versions = Versions(EndpointResponse(
        200,
        StringBuffer(jsonEncode({
          'name': 'test_package',
          'isDiscontinued': false,
          'replacedBy': '',
          'latest': version,
          'versions': [version],
        })),
        CommandType.pub));
    expect(versions.name, 'test_package');
    expect(versions.latest.retracted, isTrue);
    expect(versions.versions.single.archiveUrl, archive);
  });
}
