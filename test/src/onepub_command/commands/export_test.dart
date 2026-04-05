@Tags(['onepub_command', 'integration'])
library;
/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'package:dcli_terminal/dcli_terminal.dart';
import 'package:onepub/src/onepub_settings.dart';
import 'package:onepub/src/version/version.g.dart';
import 'package:strings/strings.dart';
import 'package:test/test.dart';

import '../../../impersonate_user.dart';
import '../../../test_users.dart';
import 'test_utils.dart';

bool _hasProvisionedRoleCoverage() {
  if (!TestUsers.initialised) {
    return false;
  }
  final users = TestUsers();
  final adminEmail = users.administrator.email;
  return users.teamLeader.email != adminEmail &&
      users.basicMember.email != adminEmail;
}

void _expectPermissionDeniedOutput(List<String> lines) {
  final lowered = lines.map((line) => line.toLowerCase()).toList();
  expect(
    lowered.any((line) =>
        line.contains('forbidden') ||
        line.contains('permission') ||
        line.contains('unauthorized')),
    isTrue,
  );
  expect(lines.any((line) => line.startsWith('ONEPUB_TOKEN=')), isFalse);
}

void main() {
  setUpAll(() async {
    await TestUsers(init: true).init();
  });
  test('onepub export env...', () async {
    // await withTestSettings((testSettings) async {

    await impersonateMember(
        member: TestUsers().administrator,
        action: () async {
          final clean = runCmd('export');

          final settings = OnePubSettings.use();
          final organisationName = settings.organisationName;

          final first = clean.first;
          expect(first, 'OnePub version: $packageVersion ');

          expect(
              clean.contains('Exporting OnePub token for $organisationName.'),
              isTrue);

          expect(
              clean.contains(
                  'Add the following environment variable to your CI/CD secrets.'),
              isTrue);

          final last = clean[(clean.length - 2)];
          validateToken(last);
        });
  });
  // });

  test('onepub export CI/CD...', () async {
    // await withTestSettings((testSettings) async {
    await impersonateMember(
        member: TestUsers().administrator,
        action: () async {
          final cicdUser = TestUsers().basicMember.email;
          final lines = runCmd('export --user $cicdUser');

          final onepubSettings = OnePubSettings.use();
          final organisationName = onepubSettings.organisationName;

          /// remove empty lines and ansi chars.
          final clean =
              lines.where(Strings.isNotEmpty).map(Ansi.strip).toList();

          final first = clean.first;
          expect(first, 'OnePub version: $packageVersion ');

          expect(
              clean.contains('Exporting OnePub token for $organisationName.'),
              isTrue);

          expect(
              clean.contains(
                  'Add the following environment variable to your CI/CD secrets.'),
              isTrue);

          final last = clean[(clean.length - 1)];

          validateToken(last);
        });
  });

  test('onepub export CI/CD denied for non-admin members', () async {
    if (!_hasProvisionedRoleCoverage()) {
      return;
    }

    final users = TestUsers();
    final targetEmail = users.administrator.email;
    final restrictedMembers = <({String roleLabel, String email})>[
      (roleLabel: 'team leader', email: users.teamLeader.email),
      (roleLabel: 'collaborator', email: users.basicMember.email),
    ];

    for (final restricted in restrictedMembers) {
      await impersonateMember(
          member: restricted.email == users.teamLeader.email
              ? users.teamLeader
              : users.basicMember,
          action: () async {
            final result = runCmdResult('export --user $targetEmail');

            expect(
              result.exitCode,
              isNonZero,
              reason:
                  '${restricted.roleLabel} unexpectedly exported $targetEmail',
            );
            _expectPermissionDeniedOutput(result.lines);
          });
    }
  });
}

void validateToken(String line) {
  const tokenPrefix = 'ONEPUB_TOKEN=';
  expect(line.startsWith(tokenPrefix), isTrue);

  // check the secret is a guid
  final token = line.substring(tokenPrefix.length);
  expect(token.length, equals(56));
}
