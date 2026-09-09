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

  AuthResponse._internal();

  factory AuthResponse.parse(EndpointResponse response) {
    final auth = AuthResponse._internal();
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

enum AwaitLoginStatus {
  authSucceeded,
  authFailed,

  /// the auth hasn't yet been completed.
  /// wait for pollInterval seconds and retry.
  retry,

  /// The auth has been cancelled as the user
  /// didn't respond in a timely manner (usually five minutes)
  timeout
}

AwaitLoginStatus parseStatus(String name) => AwaitLoginStatus.values.firstWhere(
      (e) => e.name == name.split('.').last,
      orElse: () => throw APIException('Invalid login status'),
    );
