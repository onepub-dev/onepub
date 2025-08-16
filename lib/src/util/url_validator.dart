import 'dart:math';

import 'package:dcli_input/dcli_input.dart';
import 'package:dcli_terminal/dcli_terminal.dart';
import 'package:validators2/validators2.dart';

class UrlValidator extends AskValidator {
  @override
  Future<String> validate(String line, {String? customErrorMessage}) async {
    final finalLine = line.trim().toLowerCase();

    if (!line.startsWith('https://')) {
      throw AskValidatorException(red('Must start with https://'));
    }
    final fqdn = finalLine.replaceFirst('https://', '');
    if (!isFQDN(fqdn)) {
      throw AskValidatorException(red('Invalid FQDN.'));
    }
    return finalLine;
  }
}

///
class RulesException implements Exception {
  String message;

  ///
  RulesException(this.message);

  @override
  String toString() => message;
}

String generateRandomString(int len) {
  final r = Random();
  const chars =
      'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz1234567890';
  return List.generate(len, (index) => chars[r.nextInt(chars.length)]).join();
}
