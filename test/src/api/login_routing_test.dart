import 'dart:convert';

import 'package:onepub/src/api/auth_response.dart';
import 'package:onepub/src/api/cli_models.dart';
import 'package:onepub/src/api/login_request.dart';
import 'package:onepub/src/api/status.dart';
import 'package:onepub/src/exceptions.dart';
import 'package:onepub/src/util/send_command.dart';
import 'package:test/test.dart';

AuthResponse success({Object? routing}) => AuthResponse.parse(
      EndpointResponse(
          200,
          StringBuffer(jsonEncode({
            'body': {
              'status': 'authSucceeded',
              'onePubToken': 'test-token',
              'firstLogin': false,
              'operatorEmail': 'member@example.test',
              'organisationName': 'Example',
              'obfuscatedOrganisationId': 'org-123',
              if (routing != null) 'loginRouting': routing,
            },
          })),
          CommandType.cli),
    );

void main() {
  test('old servers reject explicit SSO but accept remembered fallback', () {
    final fixed = LoginRequest.sso('acme');
    final remembered = LoginRequest.remembered(VerifiedLoginRouting.parse({
      'method': 'sso',
      'organisationCode': 'acme',
      'organisationId': 'org-123',
    }, 'org-123'));
    expect(() => fixed.forServer(supportsEnterpriseSso: false),
        throwsA(isA<ExitException>()));
    expect(remembered.forServer(supportsEnterpriseSso: false), isNull);
    expect(
        const LoginRequest.ordinary().forServer(supportsEnterpriseSso: false),
        isNull);
    expect(fixed.forServer(supportsEnterpriseSso: true), same(fixed));
  });
  test('explicit and remembered requests have different routing constraints',
      () {
    expect(LoginRequest.sso(' ACME ').queryParameters, {
      'routingMode': 'fixed',
      'loginMethod': 'sso',
      'organisationCode': 'acme',
    });
    final routing = success(routing: {
      'method': 'sso',
      'organisationId': 'org-123',
      'organisationCode': 'acme',
    }).loginRouting!;
    expect(LoginRequest.remembered(routing).queryParameters, {
      'routingMode': 'hint',
      'loginMethod': 'sso',
      'organisationCode': 'acme',
      'organisationId': 'org-123',
    });
    expect(
        const LoginRequest.choose().queryParameters, {'routingMode': 'choose'});
    expect(() => LoginRequest.sso('../acme'), throwsA(isA<ExitException>()));
  });
  test('old server success does not imply an SSO preference', () {
    expect(success().loginRouting, isNull);
    final body =
        CliStatusBody.fromJson({'message': 'healthy', 'version': '1.0.0'});
    expect(body.capabilities, isEmpty);
    expect(Status(200, 'healthy', '1.0.0').supportsEnterpriseSso, isFalse);
  });

  test('new server confirms method and credential organisation', () {
    final result = success(routing: {
      'method': 'sso',
      'organisationId': 'org-123',
      'organisationCode': 'acme',
      'futureField': true,
    });
    expect(result.loginRouting?.organisationCode, 'acme');
    expect(
        result.loginRouting?.organisationId, result.obfuscatedOrganisationId);
    final ordinary =
        success(routing: {'method': 'ordinary', 'organisationId': 'org-123'});
    expect(ordinary.loginRouting?.method, 'ordinary');
    expect(ordinary.loginRouting?.organisationCode, isNull);
    final body = CliStatusBody.fromJson({
      'message': 'healthy',
      'version': '1.0.0',
      'capabilities': ['enterprise-sso-v1', 'future-capability'],
    });
    expect(
        Status(200, body.message, body.version, capabilities: body.capabilities)
            .supportsEnterpriseSso,
        isTrue);
  });

  test('inconsistent or malformed routing cannot become a preference', () {
    for (final routing in <Object>[
      'sso',
      {
        'method': 'sso',
        'organisationId': 'other-org',
        'organisationCode': 'acme'
      },
      {'method': 'sso', 'organisationId': 'org-123'},
      {
        'method': 'sso',
        'organisationId': 'org-123',
        'organisationCode': '../acme'
      },
      {'method': 'sso', 'organisationId': 'org-123', 'organisationCode': 42},
      {'method': 'unknown', 'organisationId': 'org-123'},
      {
        'method': 'ordinary',
        'organisationId': 'org-123',
        'organisationCode': 'acme'
      },
    ]) {
      expect(() => success(routing: routing), throwsA(isA<APIException>()));
    }
  });
}
