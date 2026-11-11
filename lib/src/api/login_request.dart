import '../exceptions.dart';
import 'auth_response.dart';

/// Routing intent only. The server freezes and independently verifies it.
class LoginRequest {
  final String? method;
  final String? organisationCode;
  final String? organisationId;
  final String mode;

  const LoginRequest._(
      this.method, this.organisationCode, this.organisationId, this.mode);

  const LoginRequest.choose() : this._(null, null, null, 'choose');

  const LoginRequest.ordinary() : this._('ordinary', null, null, 'fixed');

  factory LoginRequest.sso(String code) {
    final normalized = code.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$').hasMatch(normalized)) {
      throw ExitException(
          exitCode: 1, message: 'Enter a valid organisation SSO code.');
    }
    return LoginRequest._('sso', normalized, null, 'fixed');
  }

  factory LoginRequest.remembered(VerifiedLoginRouting routing) =>
      LoginRequest._(
        routing.method,
        routing.organisationCode,
        routing.method == 'sso' ? routing.organisationId : null,
        'hint',
      );

  Map<String, String> get queryParameters => {
        'routingMode': mode,
        if (method != null) 'loginMethod': method!,
        if (organisationCode != null) 'organisationCode': organisationCode!,
        if (organisationId != null) 'organisationId': organisationId!,
      };

  /// Old servers can still show ordinary login; only an explicit SSO request
  /// must fail rather than silently changing the user's chosen method.
  LoginRequest? forServer({required bool supportsEnterpriseSso}) {
    if (supportsEnterpriseSso) {
      return this;
    }
    if (method == 'sso' && mode == 'fixed') {
      throw ExitException(
          exitCode: 1,
          message: 'This OnePub server does not support enterprise SSO login. '
              'Ask your administrator to update the server, '
              'or use onepub login browser.');
    }
    return null;
  }
}
