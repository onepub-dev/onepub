import 'dart:math';

import 'package:dcli/dcli.dart';
import 'package:validators2/validators.dart';

class UrlValidator extends AskValidator {
  @override
  String validate(String line) {
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
  ///
  RulesException(this.message);
  String message;

  @override
  String toString() => message;
}

String generateRandomString(int len) {
  final r = Random();
  const _chars =
      'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz1234567890';
  return List.generate(len, (index) => _chars[r.nextInt(_chars.length)]).join();
}
