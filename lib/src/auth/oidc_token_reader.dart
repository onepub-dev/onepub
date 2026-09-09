import 'dart:io';

import 'oidc_token_acquirer.dart';

class OidcTokenReader {
  OidcTokenReader({
    Map<String, String>? environment,
    String? Function()? readStdin,
  })  : environment = environment ?? Platform.environment,
        readStdin = readStdin ?? stdin.readLineSync;

  final Map<String, String> environment;
  final String? Function() readStdin;

  String fromEnvironment(String name) {
    final value = environment[name];
    if (value == null || value.isEmpty) {
      throw FormatException('The $name environment variable is empty.');
    }
    return OidcTokenAcquirer.validate(value);
  }

  String fromStandardInput() {
    final value = readStdin();
    if (value == null) {
      throw const FormatException(
        'No OIDC JWT was provided on standard input.',
      );
    }
    return OidcTokenAcquirer.validate(value);
  }

  String fromFile(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw FormatException("The OIDC token file '$path' does not exist.");
    }
    if (file.lengthSync() > 32768) {
      throw const FormatException('The supplied OIDC token is too large.');
    }
    return OidcTokenAcquirer.validate(file.readAsStringSync());
  }
}
