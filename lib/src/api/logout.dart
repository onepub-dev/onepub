import '../util/send_command.dart';

class Logout {
  Logout(EndpointResponse response) {
    success = response.success;

    if (!success) {
      errorMessage = response.data['message']! as String;
      // if we failed because we were already logged out
      // we still report success.
      if (errorMessage!.startsWith('Your token is no longer valid') ||
          errorMessage!
              .startsWith('You must be logged in to run this command.')) {
        wasAlreadyLoggedOut = true;
        errorMessage = null;
        success = true;
      }
    } else {
      wasAlreadyLoggedOut = false;
    }
  }

  late final bool success;

  /// If the call failed this contains the error message.
  late final String? errorMessage;

  /// If the user was already logged out when we called logout.
  late final bool wasAlreadyLoggedOut;
}
