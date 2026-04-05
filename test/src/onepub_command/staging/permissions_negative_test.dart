@Tags(['onepub_command', 'integration', 'staging'])
library;

import 'dart:io';

import 'package:onepub/src/api/api.dart';
import 'package:onepub/src/api/member.dart';
import 'package:onepub/src/util/send_command.dart';
import 'package:test/test.dart';

import '../../../test_users.dart';
import 'staging_common.dart';

Future<void> _expectDenied(
  EndpointResponse response, {
  required String action,
  required String roleLabel,
}) async {
  if (response.success) {
    throw StateError('$roleLabel unexpectedly succeeded: $action');
  }
  if (response.status != HttpStatus.forbidden &&
      response.status != HttpStatus.unauthorized) {
    throw StateError(
      '$roleLabel expected 401/403 for $action, got ${response.status}.',
    );
  }
}

Future<String> _exportTokenOrThrow(String email) async {
  final tokenResponse = await API().exportMemberToken(email);
  if (!tokenResponse.success || tokenResponse.token == null) {
    throw StateError(
      'Unable to export token for $email: ${tokenResponse.errorMessage}',
    );
  }
  return tokenResponse.token!;
}

Future<List<({String roleLabel, Member member, String token})>>
    _restrictedMembers() async {
  final users = TestUsers();
  return <({String roleLabel, Member member, String token})>[
    (
      roleLabel: 'team leader',
      member: users.teamLeader,
      token: await _exportTokenOrThrow(users.teamLeader.email),
    ),
    (
      roleLabel: 'collaborator',
      member: users.basicMember,
      token: await _exportTokenOrThrow(users.basicMember.email),
    ),
  ];
}

bool _hasProvisionedRoleCoverage() {
  if (!TestUsers.initialised) {
    return false;
  }
  final users = TestUsers();
  final adminEmail = users.administrator.email;
  return users.teamLeader.email != adminEmail &&
      users.basicMember.email != adminEmail;
}

void main() {
  final config = StagingConfig.fromEnv();
  setUpAll(() => ensureTestUsers(config));

  test('team members cannot export other member tokens', () async {
    if (!_hasProvisionedRoleCoverage()) {
      stdout.writeln(
        'Skipping permission test: requires system-admin provisioned users '
        'with distinct non-admin roles.',
      );
      return;
    }

    await withAdmin(config, (context) async {
      final targetEmail = TestUsers().administrator.email;
      final restrictedMembers = await _restrictedMembers();
      for (final restricted in restrictedMembers) {
        await withScopedMemberToken(
          onepubUrl: context.onepubUrl,
          member: restricted.member,
          token: restricted.token,
          action: (_) async {
            final response = await sendCommand(
              command: 'member/exportToken/${Uri.encodeComponent(targetEmail)}',
              commandType: CommandType.cli,
            );
            await _expectDenied(
              response,
              action: 'exporting $targetEmail token',
              roleLabel: restricted.roleLabel,
            );
          },
        );
      }
    });
  },
      timeout: const Timeout(Duration(minutes: 5)),
      skip: config.skipUnauthorizedTest);

  test('team members cannot create members', () async {
    if (!_hasProvisionedRoleCoverage()) {
      stdout.writeln(
        'Skipping permission test: requires system-admin provisioned users '
        'with distinct non-admin roles.',
      );
      return;
    }

    await withAdmin(config, (context) async {
      final restrictedMembers = await _restrictedMembers();
      for (final restricted in restrictedMembers) {
        final roleSlug = restricted.roleLabel.replaceAll(' ', '_');
        final timestamp = DateTime.now().microsecondsSinceEpoch;
        final email = 'forbidden_${roleSlug}_$timestamp@testdomain.com';
        final command = 'member/create'
            '?email=${Uri.encodeQueryComponent(email)}'
            '&firstname=Denied'
            '&lastname=User'
            '&role=Collaborator';
        await withScopedMemberToken(
          onepubUrl: context.onepubUrl,
          member: restricted.member,
          token: restricted.token,
          action: (_) async {
            final response = await sendCommand(
              command: command,
              commandType: CommandType.cli,
            );
            await _expectDenied(
              response,
              action: 'creating member $email',
              roleLabel: restricted.roleLabel,
            );
          },
        );
      }
    });
  },
      timeout: const Timeout(Duration(minutes: 5)),
      skip: config.skipUnauthorizedTest);
}
