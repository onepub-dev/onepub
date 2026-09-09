@Tags(['onepub_command', 'integration', 'staging'])
library;

import 'dart:io';

import 'package:onepub/src/api/api.dart';
import 'package:onepub/src/api/member.dart';
import 'package:onepub/src/util/one_pub_token_store.dart';
import 'package:onepub/src/util/send_command.dart';
import 'package:test/test.dart';

import '../../../test_users.dart';
import 'staging_common.dart';

Future<void> tokenInvalidationTest() async {
  stdout.writeln('Testing token invalidation...');
  final tokenStore = OnePubTokenStore();
  final token = await tokenStore.load();

  final logoutResponse = await sendCommand(
    command: 'member/logout',
    commandType: CommandType.cli,
  );
  if (!logoutResponse.success) {
    stderr.writeln('Logout failed: ${logoutResponse.errorMessage}');
    throw StateError('Logout failed for token invalidation test.');
  }

  final response = await sendCommand(
    command: 'organisation/details',
    commandType: CommandType.cli,
    authorised: false,
    headers: <String, String>{'authorization': token},
  );

  if (response.success) {
    throw StateError('Token invalidation test failed: token still valid.');
  }

  if (response.status != 401 && response.status != 403) {
    throw StateError(
        'Token invalidation test failed: expected 401/403, got ${response.status}.');
  }
}

Future<Member> _memberForTokenInvalidation() async => TestUsers().basicMember;

void main() {
  final config = StagingConfig.fromEnv();
  setUpAll(() => ensureTestUsers(config));

  test('token invalidation', () async {
    if (!TestUsers.initialised) {
      stdout.writeln(
          'Skipping token invalidation: requires provisioned test users.');
      return;
    }
    await withAdmin(config, (context) async {
      final member = await _memberForTokenInvalidation();
      final tokenResponse = await API().exportTestMemberToken(
        obfuscatedOrganisationId: member.obfuscatedOrganisationId,
        memberEmail: member.email,
      );
      if (!tokenResponse.success || tokenResponse.token == null) {
        throw StateError('''
Unable to export token for ${member.email}: ${tokenResponse.errorMessage}''');
      }
      final onepubUrl =
          config.stagingUrl.isEmpty ? context.onepubUrl : config.stagingUrl;
      await withScopedMemberToken(
        onepubUrl: onepubUrl,
        member: member,
        token: tokenResponse.token!,
        action: (_) => tokenInvalidationTest(),
      );
    });
  },
      timeout: const Timeout(Duration(minutes: 5)),
      skip: config.skipTokenInvalidation);
}
