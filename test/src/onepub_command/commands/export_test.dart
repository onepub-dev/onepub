@Tags(['onepub_command', 'integration'])
library;
/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'dart:convert';

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
        line.contains('unauthorized') ||
        line.contains('privileges') ||
        line.contains('cannot export') ||
        line.contains('only team leaders')),
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

  test('onepub export CI/CD denied for collaborators exporting other members',
      () async {
    if (!_hasProvisionedRoleCoverage()) {
      return;
    }

    final users = TestUsers();
    final targetEmail = users.administrator.email;
    final collaborator = users.basicMember;

    await impersonateMember(
        member: collaborator,
        action: () async {
          final result = runCmdResult('export --user $targetEmail');

          expect(
            result.exitCode,
            isNonZero,
            reason: 'collaborator unexpectedly exported $targetEmail',
          );
          _expectPermissionDeniedOutput(result.lines);
        });
  });
}

void validateToken(String line) {
  const tokenPrefix = 'ONEPUB_TOKEN=';
  expect(line.startsWith(tokenPrefix), isTrue);

  final token = line.substring(tokenPrefix.length);
  final payload = utf8.decode(base64.decode(base64.normalize(token)));
  expect(
    payload,
    matches(RegExp(
      r'^\d+:[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-'
      r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      caseSensitive: false,
    )),
  );
}
