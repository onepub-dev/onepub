class ExitException extends OnepubCliException {
  ExitException({required this.exitCode, required String message})
      : super(message);

  int exitCode;
}

class CredentialsException extends OnepubCliException {
  CredentialsException({required String message}) : super(message);
}

class UnexpectedHttpResponseException extends OnepubCliException {
  UnexpectedHttpResponseException({required String message}) : super(message);
}

class OnepubCliException implements Exception {
  OnepubCliException(this.message);

  String message;
  @override
  String toString() => message;
}
