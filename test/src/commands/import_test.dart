/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'package:dcli/dcli.dart' hide equals;
import 'package:onepub/src/entry_point.dart';
import 'package:onepub/src/my_runner.dart';
import 'package:onepub/src/onepub_settings.dart';
import 'package:onepub/src/version/version.g.dart';
import 'package:test/test.dart';

import '../../test_settings.dart';
import 'test_utils.dart';

void main() {
  test('onepub import --file', () async {
    await withTokenFile('import --file', 'onepub.token.yaml', _runCliCommand);
  });

  test('onepub import --file afile.yaml', () async {
    await withTempFile((onepubTokenFile) async {
      await withTokenFile(
          'import --file $onepubTokenFile', onepubTokenFile, _runCliCommand);
    });
  });

  test('internal onepub import --file afile.yaml', () async {
    await withTempFile((onepubTokenFile) async {
      await withTokenFile('import --file $onepubTokenFile', onepubTokenFile,
          _runInternalCommand);
    });
  });
}

Future<void> withTokenFile(String command, String pathToImportFile,
    Future<List<String>> Function(String command) run) async {
  await withTestSettings((testSettings) async {
    final onepubToken = testSettings.onepubToken;
    final settings = OnePubSettings.use;
    final organisationName = settings.organisationName;

    pathToImportFile.write('''
  # SettingsYaml settings file
  onepubToken: "$onepubToken"
  ''');

    final clean = await run(command);

    // check the cli output from the import command.
    final first = clean.first;
    expect(first, 'OnePub version: $packageVersion ');

    expect(
        clean.contains('Successfully logged into $organisationName.'), isTrue);
  });
}

Future<List<String>> _runCliCommand(String command) async => runCmd(command);

Future<List<String>> _runInternalCommand(String command) async {
  final capture = Progress.capture();
  await DCliZone().run(() async {
    await entrypoint(command.split(' '), CommandSet.onepub, 'onepub');
  }, progress: capture);

  return capture.lines;
}
