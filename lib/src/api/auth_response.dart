import '../exceptions.dart';
import '../util/send_command.dart';
import 'cli_models.dart';

class AuthResponse {
  late final AwaitLoginStatus status;

  late final int pollInterval;

  late final String onepubToken;

  late final bool firstLogin;

  late final String operatorEmail;

  late final String organisationName;

  late final String obfuscatedOrganisationId;

  VerifiedLoginRouting? loginRouting;

  AuthResponse._internal();

  factory AuthResponse.parse(EndpointResponse response) {
    final auth = AuthResponse._internal();
    if (response.status == 429) {
      final retryAfter = int.tryParse(response.retryAfter?.trim() ?? '');
      auth
        ..status = AwaitLoginStatus.rateLimited
        ..pollInterval = retryAfter != null && retryAfter > 0 ? retryAfter : 5;
      return auth;
    }
    if (response.success) {
      final body = response.requireCliBody((json) {
        final status = requiredResponseString(json, 'status');
        if (parseStatus(status) == AwaitLoginStatus.authSucceeded) {
          for (final field in [
            'onePubToken',
            'operatorEmail',
            'organisationName',
            'obfuscatedOrganisationId',
          ]) {
            requiredResponseString(json, field);
          }
          if (json['firstLogin'] is! bool) {
            throw APIException(
                'Missing or invalid response field "firstLogin"');
          }
          final Object? routing = json['loginRouting'];
          if (routing != null) {
            auth.loginRouting = VerifiedLoginRouting.parse(
              routing,
              requiredResponseString(json, 'obfuscatedOrganisationId'),
            );
          }
        }
        return CliAuthBody.fromJson(json);
      });
      auth.status = parseStatus(body.status);

      switch (auth.status) {
        case AwaitLoginStatus.authSucceeded:
          auth
            ..onepubToken = body.onePubToken
            ..firstLogin = body.firstLogin
            ..operatorEmail = body.operatorEmail
            ..organisationName = body.organisationName
            ..obfuscatedOrganisationId = body.obfuscatedOrganisationId;
        case AwaitLoginStatus.retry:
          auth.pollInterval = body.pollInterval > 0 ? body.pollInterval : 3;
        case AwaitLoginStatus.rateLimited:
          auth.pollInterval = body.pollInterval > 0 ? body.pollInterval : 5;
        case AwaitLoginStatus.authFailed:
          throw ExitException(exitCode: 1, message: 'Authentication failed');
        case AwaitLoginStatus.timeout:
          throw ExitException(exitCode: 1, message: 'Login Timed out');
      }
      return auth;
    } else {
      throw ExitException(
          exitCode: 1, message: 'Login failed: ${response.errorMessage}');
    }
  }
}

/// Server-confirmed routing for the issued credential, never a request hint.
class VerifiedLoginRouting {
  final String method;
  final String organisationId;
  final String? organisationCode;

  VerifiedLoginRouting._(
      this.method, this.organisationId, this.organisationCode);

  factory VerifiedLoginRouting.parse(
      Object value, String credentialOrganisation) {
    if (value is! Map<String, dynamic>) {
      throw APIException('Invalid login routing response');
    }
    final method = requiredResponseString(value, 'method');
    final organisationId = requiredResponseString(value, 'organisationId');
    final code = value['organisationCode'];
    if (organisationId != credentialOrganisation ||
        (method != 'ordinary' && method != 'sso') ||
        (method == 'ordinary' && code != null) ||
        (method == 'sso' &&
            (code is! String ||
                !RegExp(r'^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$')
                    .hasMatch(code)))) {
      throw APIException('Invalid login routing response');
    }
    return VerifiedLoginRouting._(method, organisationId, code as String?);
  }
}

enum AwaitLoginStatus {
  authSucceeded,
  authFailed,

  /// the auth hasn't yet been completed.
  /// wait for pollInterval seconds and retry.
  retry,

  /// The server asked this network to wait before another login poll.
  rateLimited,

  /// The auth has been cancelled as the user
  /// didn't respond in a timely manner (usually five minutes)
  timeout
}

AwaitLoginStatus parseStatus(String name) => AwaitLoginStatus.values.firstWhere(
      (e) => e.name == name.split('.').last,
      orElse: () => throw APIException('Invalid login status'),
    );
