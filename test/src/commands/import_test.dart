/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'dart:async';

import 'package:dcli/dcli.dart' as dcli;
import 'package:dcli_core/dcli_core.dart' as core;
import 'package:dcli_terminal/dcli_terminal.dart';
import 'package:onepub/src/api/member.dart';
import 'package:onepub/src/onepub_settings.dart';
import 'package:onepub/src/version/version.g.dart';
import 'package:strings/strings.dart';
import 'package:test/test.dart';

import '../../impersonate_user.dart';
import '../../test_users.dart';
import 'test_utils.dart';

void main() {
  setUpAll(() async {
    await TestUsers(init: true).init();
  });
  test('onepub import --file', () async {
    final member = TestUsers().administrator;
    await impersonateMember(
        member: member,
        action: () async {
          await withTokenImportFile(
              member, 'import --file', 'onepub.token.yaml', _runCliCommand);
        });
  });

  test('onepub import --file afile.yaml', () async {
    final member = TestUsers().administrator;
    await impersonateMember(
        member: member,
        action: () async {
          await core.withTempFileAsync((onepubTokenFile) async {
            await withTokenImportFile(member, 'import --file $onepubTokenFile',
                onepubTokenFile, _runCliCommand);
          });
        });
  });

  // TODO(bsutton): restore after dcli deals with waitfor issue.
  // test('internal onepub import --file afile.yaml', () async {
  //   final member = TestUsers().administrator;
  //   await impersonateMember(
  //       member: member,
  //       action: () async {
  //         await core.withTempFileAsync((onepubTokenFile) async {
  //           await withTokenImportFile(member, 'import --file $onepubTokenFile',
  //               onepubTokenFile, _runInternalCommand);
  //         });
  //       });
  // });
}

/// Creates a yaml containing a onepubToken suitable for use
/// with the onepub import command
Future<void> withTokenImportFile(
    Member member,
    String command,
    String pathToImportFile,
    Future<List<String>> Function(String command) run) async {
//  await withTestSettings((testSettings) async {
  final onepubToken = member.onepubToken;
  final settings = OnePubSettings.use();
  final organisationName = settings.organisationName;

  pathToImportFile.write('''
  # SettingsYaml settings file
  onepubToken: "$onepubToken"
  ''');

  final lines = await run(command);
  final cleaned = lines.where(Strings.isNotEmpty).map(Ansi.strip).toList();

  expect(cleaned.length, 3);

  // check the cli output from the import command.
  final first = cleaned.first;
  expect(first, 'OnePub version: $packageVersion ');

  expect(
      cleaned.contains('Successfully logged into $organisationName.'), isTrue);
  //});
}

Future<List<String>> _runCliCommand(String command) async => runCmd(command);

// TODO(bsutton): restore this functionality once dcli has fixed the wait for issue.
// Future<List<String>> _runInternalCommand(String command) async {
//   final progress = dcli.Progress.capture();

//   await capture(() async {
//     await entrypoint(command.split(' '), CommandSet.onepub, 'onepub');
//   }, progress: progress);

//   return progress.lines;
// }

// int call = 0;
// int count = 0;
// Future<void> _tester(String debug) {
//   final a = Completer<bool>();
//   print('call: $call count: $count debug: $debug');
//   call++;
//   count++;

//   Future.delayed(const Duration(seconds: 3), () {
//     count--;
//     print('completed: $count debug: $debug');
//     a.complete(true);
//   });

//   return a.future;
// }
