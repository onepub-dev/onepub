import 'dart:io';

import 'package:onepub/src/auth/oidc_token_reader.dart';
import 'package:test/test.dart';

void main() {
  const jwt = 'header.payload.signature';

  test('reads a JWT from a named environment variable', () {
    final reader = OidcTokenReader(environment: {'CUSTOM_ID_TOKEN': jwt});

    expect(reader.fromEnvironment('CUSTOM_ID_TOKEN'), jwt);
    expect(
      () => reader.fromEnvironment('MISSING_TOKEN'),
      throwsFormatException,
    );
  });

  test('reads a JWT from standard input', () {
    final reader = OidcTokenReader(
      environment: const {},
      readStdin: () => '  $jwt\n',
    );

    expect(reader.fromStandardInput(), jwt);
  });

  test('reads a JWT from a bounded file', () {
    final temp = File('${Directory.systemTemp.path}/'
        'onepub-oidc-token-${DateTime.now().microsecondsSinceEpoch}.jwt')
      ..writeAsStringSync('$jwt\n');
    addTearDown(temp.deleteSync);
    final reader = OidcTokenReader(environment: const {});

    expect(reader.fromFile(temp.path), jwt);
  });
}
