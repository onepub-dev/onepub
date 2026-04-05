@Tags(['onepub_command', 'integration', 'staging'])
library;

import 'dart:io';

import 'package:onepub/src/util/send_command.dart';
import 'package:test/test.dart';

import '../../../test_users.dart';
import 'staging_common.dart';

Future<void> teamNegativeTest({
  required String teamName,
  required String packagePrefix,
  bool expectForbidden = false,
}) async {
  final suffix = DateTime.now().toUtc().millisecondsSinceEpoch;
  final packageName = '${packagePrefix}_badteam_$suffix';

  stdout.writeln(
      'Testing team scoping with invalid team "$teamName" for $packageName...');
  final encodedTeam = Uri.encodeQueryComponent(teamName);
  final response = await sendCommand(
    command: 'test/package/create/$packageName?team=$encodedTeam',
    commandType: CommandType.cli,
    method: Method.post,
  );

  if (response.success) {
    throw StateError(
        'Team scoping test failed: package creation succeeded unexpectedly.');
  }

  if (expectForbidden && response.status != HttpStatus.forbidden) {
    throw StateError(
      'Team scoping test failed: expected HTTP 403, got ${response.status}.',
    );
  }
}

void main() {
  final config = StagingConfig.fromEnv();
  setUpAll(() => ensureTestUsers(config));

  test('team negative', () async {
    await withAdmin(config, (context) async {
      await teamNegativeTest(
        teamName: config.invalidTeam,
        packagePrefix: config.packagePrefix,
      );
    });
  },
      timeout: const Timeout(Duration(minutes: 5)),
      skip: config.skipTeamNegative);

  test('team membership negative', () async {
    if (!TestUsers.initialised) {
      stdout.writeln(
        'Skipping team membership negative test: requires provisioned '
        'test users.',
      );
      return;
    }

    await withAdmin(config, (context) async {
      final forbiddenTeam = await resolveForbiddenTeam(config);
      if (forbiddenTeam == null) {
        stdout.writeln(
          'Skipping team membership negative test: no non-everyone team '
          'available beyond the publish team.',
        );
        return;
      }

      final collaborator = TestUsers().basicMember;
      final token = collaborator.onepubToken;
      await withScopedMemberToken(
        onepubUrl: context.onepubUrl,
        member: collaborator,
        token: token,
        action: (_) async {
          await teamNegativeTest(
            teamName: forbiddenTeam,
            packagePrefix: config.packagePrefix,
            expectForbidden: true,
          );
        },
      );
    });
  },
      timeout: const Timeout(Duration(minutes: 5)),
      skip: config.skipTeamNegative);
}
