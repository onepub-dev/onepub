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
      final envelope = response.parseCli(CliAuthBody.fromJson);
      final body = envelope.body;
      auth.status =
          parseStatus(body?.status ?? AwaitLoginStatus.authFailed.name);

      switch (auth.status) {
        case AwaitLoginStatus.authSucceeded:
          auth
            ..onepubToken = body?.onePubToken ?? ''
            ..firstLogin = body?.firstLogin ?? false
            ..operatorEmail = body?.operatorEmail ?? ''
            ..organisationName = body?.organisationName ?? ''
            ..obfuscatedOrganisationId = body?.obfuscatedOrganisationId ?? '';
        case AwaitLoginStatus.retry:
          auth.pollInterval = body?.pollInterval ?? 3;
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
    (e) => e.toString() == 'AwaitLoginStatus.${name.split('.').last}');
