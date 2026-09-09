@Tags(['onepub_command', 'integration', 'staging'])
library;

import 'dart:io';

import 'package:onepub/src/api/api.dart';
import 'package:onepub/src/api/cli_models.dart';
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

Future<void> _expectAllowed(
  EndpointResponse response, {
  required String action,
  required String roleLabel,
}) async {
  if (!response.success) {
    throw StateError(
      '$roleLabel unexpectedly failed: $action. ${response.errorMessage}',
    );
  }
  final body = response.parseCli(CliExportTokenBody.fromJson).body;
  if (body == null || body.onepubToken.isEmpty) {
    throw StateError(
      '$roleLabel did not receive a token while $action.',
    );
  }
}

Future<EndpointResponse> _exportTokenResponse(String email) => sendCommand(
      command: 'member/exportToken/${Uri.encodeComponent(email)}',
      commandType: CommandType.cli,
    );

Future<String> _exportTokenOrThrow(String email, String organisationId) async {
  final tokenResponse = await API().exportTestMemberToken(
    obfuscatedOrganisationId: organisationId,
    memberEmail: email,
  );
  if (!tokenResponse.success || tokenResponse.token == null) {
    throw StateError(
      'Unable to export token for $email: ${tokenResponse.errorMessage}',
    );
  }
  return tokenResponse.token!;
}

Future<String> _exportScopedTestTokenOrThrow(Member member) async {
  final tokenResponse = await API().exportTestMemberToken(
    obfuscatedOrganisationId: member.obfuscatedOrganisationId,
    memberEmail: member.email,
  );
  if (!tokenResponse.success || tokenResponse.token == null) {
    throw StateError(
      'Unable to export scoped test token for ${member.email}: '
      '${tokenResponse.errorMessage}',
    );
  }
  return tokenResponse.token!;
}

Future<Member> _createMemberByRoleName({
  required String email,
  required String roleName,
}) async {
  final command = 'test/member/create'
      '?email=${Uri.encodeQueryComponent(email)}'
      '&firstname=Permission'
      '&lastname=${Uri.encodeQueryComponent(roleName)}'
      '&role=${Uri.encodeQueryComponent(roleName)}';
  final response = await sendCommand(
    command: command,
    commandType: CommandType.cli,
  );
  if (!response.success) {
    throw StateError(
      'Unable to create $roleName member $email: ${response.errorMessage}',
    );
  }
  final body = response.parseCli(CliMemberBody.fromJson).body;
  if (body == null) {
    throw StateError('Missing body while creating $roleName member $email.');
  }
  return Member(
    email: body.email,
    firstname: body.firstname,
    lastname: body.lastname,
    roles: {},
    organisationName: body.organisationName,
    obfuscatedOrganisationId: body.obfuscateOrganisationId,
    onepubToken:
        await _exportTokenOrThrow(body.email, body.obfuscateOrganisationId),
  );
}

Future<void> _asMember({
  required String onepubUrl,
  required Member member,
  required Future<void> Function() action,
}) async {
  await withScopedMemberToken(
    onepubUrl: onepubUrl,
    member: member,
    token: await _exportScopedTestTokenOrThrow(member),
    action: (_) => action(),
  );
}

Future<List<({String roleLabel, Member member, String token})>>
    _restrictedMembers() async {
  final users = TestUsers();
  final freshTeamLeader = await users.createTeamLeader(_uniqueEmail(
    'permission-denied-leader',
  ));
  return <({String roleLabel, Member member, String token})>[
    (
      roleLabel: 'team leader',
      member: freshTeamLeader,
      token: await _exportTokenOrThrow(
        freshTeamLeader.email,
        freshTeamLeader.obfuscatedOrganisationId,
      ),
    ),
    (
      roleLabel: 'collaborator',
      member: users.basicMember,
      token: await _exportTokenOrThrow(
        users.basicMember.email,
        users.basicMember.obfuscatedOrganisationId,
      ),
    ),
  ];
}

String _uniqueEmail(String prefix) {
  final timestamp = DateTime.now().microsecondsSinceEpoch;
  return '$prefix-$timestamp@testdomain.com';
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

  test('token export enforces identity role-rank boundaries', () async {
    if (!_hasProvisionedRoleCoverage()) {
      stdout.writeln(
        'Skipping permission test: requires system-admin provisioned users '
        'with distinct non-admin roles.',
      );
      return;
    }

    await withAdmin(config, (context) async {
      final users = TestUsers();
      final peerAdmin = await users.createAdministrator(_uniqueEmail(
        'permission-peer-admin',
      ));
      final peerTeamLeader = await users.createTeamLeader(_uniqueEmail(
        'permission-peer-leader',
      ));
      final cicdMember = await _createMemberByRoleName(
        email: _uniqueEmail('permission-cicd'),
        roleName: 'CICD',
      );
      final customer = await _createMemberByRoleName(
        email: _uniqueEmail('permission-customer'),
        roleName: 'Customer',
      );
      final uploader = await _createMemberByRoleName(
        email: _uniqueEmail('permission-uploader'),
        roleName: 'Uploader',
      );

      final admin = users.administrator;
      final teamLeader = users.teamLeader;
      final collaborator = users.basicMember;

      await _asMember(
        onepubUrl: context.onepubUrl,
        member: admin,
        action: () async {
          await _expectAllowed(
            await _exportTokenResponse(admin.email),
            action: 'exporting own token',
            roleLabel: 'administrator',
          );

          await _expectAllowed(
            await _exportTokenResponse(teamLeader.email),
            action: 'exporting lower-ranked team leader token',
            roleLabel: 'administrator',
          );

          await _expectAllowed(
            await _exportTokenResponse(collaborator.email),
            action: 'exporting lower-ranked collaborator token',
            roleLabel: 'administrator',
          );

          await _expectAllowed(
            await _exportTokenResponse(uploader.email),
            action: 'exporting lower-ranked uploader token',
            roleLabel: 'administrator',
          );

          await _expectAllowed(
            await _exportTokenResponse(cicdMember.email),
            action: 'exporting lower-ranked CI/CD member token',
            roleLabel: 'administrator',
          );

          await _expectAllowed(
            await _exportTokenResponse(customer.email),
            action: 'exporting lower-ranked customer token',
            roleLabel: 'administrator',
          );

          await _expectDenied(
            await _exportTokenResponse(peerAdmin.email),
            action: 'exporting equal-ranked administrator token',
            roleLabel: 'administrator',
          );
        },
      );

      await _asMember(
        onepubUrl: context.onepubUrl,
        member: teamLeader,
        action: () async {
          await _expectAllowed(
            await _exportTokenResponse(teamLeader.email),
            action: 'exporting own token',
            roleLabel: 'team leader',
          );

          await _expectDenied(
            await _exportTokenResponse(collaborator.email),
            action: 'exporting lower-ranked team member token',
            roleLabel: 'team leader',
          );

          await _expectDenied(
            await _exportTokenResponse(uploader.email),
            action: 'exporting lower-ranked uploader team member token',
            roleLabel: 'team leader',
          );

          await _expectDenied(
            await _exportTokenResponse(cicdMember.email),
            action: 'exporting lower-ranked CI/CD member token',
            roleLabel: 'team leader',
          );

          await _expectDenied(
            await _exportTokenResponse(peerTeamLeader.email),
            action: 'exporting equal-ranked team leader token',
            roleLabel: 'team leader',
          );

          await _expectDenied(
            await _exportTokenResponse(admin.email),
            action: 'exporting higher-ranked administrator token',
            roleLabel: 'team leader',
          );
        },
      );

      await _asMember(
        onepubUrl: context.onepubUrl,
        member: collaborator,
        action: () async {
          await _expectAllowed(
            await _exportTokenResponse(collaborator.email),
            action: 'exporting own token',
            roleLabel: 'collaborator',
          );

          await _expectDenied(
            await _exportTokenResponse(teamLeader.email),
            action: 'exporting higher-ranked team leader token',
            roleLabel: 'collaborator',
          );

          await _expectDenied(
            await _exportTokenResponse(admin.email),
            action: 'exporting higher-ranked administrator token',
            roleLabel: 'collaborator',
          );
        },
      );

      for (final member in [uploader, cicdMember, customer]) {
        await _asMember(
          onepubUrl: context.onepubUrl,
          member: member,
          action: () async {
            await _expectDenied(
              await _exportTokenResponse(collaborator.email),
              action: 'exporting another member token',
              roleLabel: switch (member.email) {
                final email when email == uploader.email => 'uploader',
                final email when email == cicdMember.email => 'CI/CD',
                _ => 'customer',
              },
            );
          },
        );
      }
    });
  },
      timeout: const Timeout(Duration(minutes: 5)),
      skip: config.skipUnauthorizedTest);

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
        final command = 'test/member/create'
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
