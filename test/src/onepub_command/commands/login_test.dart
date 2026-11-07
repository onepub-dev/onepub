@Tags(['onepub_command'])
library;
/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'dart:async';
import 'dart:io';
import 'package:dcli_core/dcli_core.dart';
import 'package:onepub/src/commands/login.dart';
import 'package:onepub/src/entry_point.dart';
import 'package:onepub/src/onepub_settings.dart';
import 'package:onepub/src/util/one_pub_token_store.dart';
import 'package:onepub/src/util/send_command.dart';
import 'package:path/path.dart';
import 'package:test/test.dart';
import '../../../fixture_oauth.dart';
import '../../../test_settings.dart';

void main() {
  test('onepub login completes through the running test server', () async {
    await withTestServer(() async {
      final targetUrl = TestSettings.resolveOnePubUrl();
      final bootstrapToken =
          (Platform.environment['ONEPUB_BOOTSTRAP_TEST_TOKEN'] ?? '').trim();
      final authorisingToken = bootstrapToken.isNotEmpty
          ? bootstrapToken
          : await OnePubTokenStore().load();

      await withTempDirAsync((tempDir) async {
        await OnePubSettings.withPathTo(join(tempDir, 'settings'), () async {
          final settings = OnePubSettings.use()..onepubUrl = targetUrl;
          await settings.save();

          await OnePubTokenStore.withPathTo(join(tempDir, 'tokens'), () async {
            final authToken = Completer<String>();
            final output = <String>[];
            final login = runZoned(
              () => withEnvironmentAsync(
                  () => entrypoint(args: ['login'], executableName: 'onepub'),
                  environment: {
                    'ONEPUB_PATH': join(tempDir, 'settings'),
                  }),
              zoneSpecification: ZoneSpecification(
                print: (self, parent, zone, line) {
                  output.add(line);
                  final match =
                      RegExp('clilogin/([a-f0-9-]+)').firstMatch(line);
                  if (match != null && !authToken.isCompleted) {
                    authToken.complete(match.group(1)!);
                  }
                  parent.print(zone, line);
                },
              ),
            );

            final token = await authToken.future.timeout(
              const Duration(seconds: 10),
              onTimeout: () => throw StateError(
                'onepub login did not publish its browser authentication URL.',
              ),
            );
            await _completePendingLogin(token, authorisingToken, targetUrl);
            await login.timeout(const Duration(seconds: 15));

            expect(
              output.join('\n'),
              contains('Successfully logged into'),
            );
            expect(settings.operatorEmail, isNotEmpty);
            expect(
              await OnePubTokenStore().isLoggedIn(settings.onepubApiUrl),
              isTrue,
            );
          });
        });
      });
    }, resolveOrganisationToken: false);
  }, tags: ['integration']);

  test('welcome', () async {
    await withTempDirAsync((directory) async {
      await OnePubSettings.withPathTo(directory, () async {
        OnePubSettings.use().onepubUrl = 'http://127.0.0.1:54321';
        final output = <String>[];
        runZoned(
          () => showWelcome(
              firstLogin: true,
              organisationName: 'Test Org',
              operator: 'Test Operator'),
          zoneSpecification: ZoneSpecification(
            print: (self, parent, zone, line) => output.add(line),
          ),
        );
        expect(output.join('\n'),
            contains('Successfully logged into Test Org as Test Operator.'));
        expect(output.join('\n'), contains('Welcome to OnePub.'));
        expect(output.join('\n'),
            contains('http://127.0.0.1:54321/Blog?id=zuhnoflygz'));
      });
    });
  });
}

Future<void> _completePendingLogin(
  String authToken,
  String authorisingToken,
  String targetUrl,
) async {
  EndpointResponse? lastResponse;
  for (var attempt = 0; attempt < 40; attempt++) {
    lastResponse = await sendFixtureCommand(
      command: 'test/auth/completeCliLogin/$authToken',
      commandType: CommandType.cli,
      actor: authorisingToken,
      onepubUrl: targetUrl,
      method: Method.post,
    );
    if (lastResponse.success) {
      return;
    }
    if (!lastResponse.errorMessage.contains('not pending')) {
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError(
    'Unable to complete the pending CLI login: '
    '${lastResponse?.errorMessage ?? 'no response'}',
  );
}
