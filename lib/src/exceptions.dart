/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

class ExitException extends OnePubCliException {
  ExitException({required this.exitCode, required String message})
      : super(message);

  int exitCode;
}

class CredentialsException extends OnePubCliException {
  CredentialsException({required String message}) : super(message);
}

class UnexpectedHttpResponseException extends OnePubCliException {
  UnexpectedHttpResponseException({required String message}) : super(message);
}

class OnePubCliException implements Exception {
  OnePubCliException(this.message);

  String message;
  @override
  String toString() => message;
}
