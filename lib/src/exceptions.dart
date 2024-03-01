/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'dart:io';

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

class FetchException extends OnePubCliException {
  /// ctor
  FetchException(super.message) : errorCode = OSError.noErrorCode;

  /// Create an exception from a SocketException
  FetchException.fromException(SocketException e)
      : errorCode = e.osError?.errorCode,
        super(e.message);

  /// Create a FetchException as the result of a
  /// HTTP error.
  FetchException.fromHttpError(this.errorCode, String reasonPhrase)
      : super(reasonPhrase);

  /// If this [FetchException] occured due to an [OSError] then
  /// this contains the underlying error.
  int? errorCode;
}
