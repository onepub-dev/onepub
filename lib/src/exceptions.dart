/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

class ExitException extends OnePubCliException {
  ExitException({required this.exitCode, required String message})
      : super(message);

  int exitCode;
}

class CredentialsException extends OnePubCliException {
  CredentialsException(super.message);
}

class UnexpectedHttpResponseException extends OnePubCliException {
  UnexpectedHttpResponseException(super.message);
}

class OnePubCliException implements Exception {
  OnePubCliException(this.message);

  String message;
  @override
  String toString() => message;
}

class APIException extends OnePubCliException {
  APIException(super.message);
}

class NotInitialisedException extends OnePubCliException {
  NotInitialisedException(super.message);
}

class SettingsException extends OnePubCliException {
  SettingsException(super.message);
}
