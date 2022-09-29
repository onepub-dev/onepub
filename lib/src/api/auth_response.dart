import '../exceptions.dart';
import '../util/send_command.dart';

class AuthResponse {
  AuthResponse._internal();

  factory AuthResponse.parse(EndpointResponse response) {
    final auth = AuthResponse._internal();
    if (response.success == true) {
      auth.status = parseStatus(response.data['status'] as String? ??
          AwaitLoginStatus.authFailed.toString());

      switch (auth.status) {
        case AwaitLoginStatus.authSucceeded:
          auth
            ..onepubToken = response.data['onePubToken']! as String
            ..firstLogin = response.data['firstLogin']! as bool
            ..operatorEmail = response.data['operatorEmail']! as String
            ..organisationName = response.data['organisationName']! as String
            ..obfuscatedOrganisationId =
                response.data['obfuscatedOrganisationId']! as String;
          break;
        case AwaitLoginStatus.retry:
          auth.pollInterval = response.data['pollInterval'] as int? ?? 3;
          break;
        case AwaitLoginStatus.authFailed:
          throw ExitException(exitCode: 1, message: 'Authentication failed');
        case AwaitLoginStatus.timeout:
          throw ExitException(exitCode: 1, message: 'Login Timed out');
      }
      return auth;
    } else {
      var show = '';
      final error = response.data['error'] as String?;
      final message = response.data['message'] as String?;
      if (error != null) {
        show = error;
      } else if (message != null) {
        show = message;
      }

      throw ExitException(exitCode: 1, message: 'Login failed: $show');
    }
  }

  late final AwaitLoginStatus status;
  late final int pollInterval;

  late final String onepubToken;
  late final bool firstLogin;
  late final String operatorEmail;
  late final String organisationName;
  late final String obfuscatedOrganisationId;
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

AwaitLoginStatus parseStatus(String name) => AwaitLoginStatus.values
    .firstWhere((e) => e.toString() == 'AwaitLoginStatus.$name');
