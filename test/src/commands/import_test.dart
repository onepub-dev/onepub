/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'package:dcli/dcli.dart' hide equals;
import 'package:onepub/src/onepub_settings.dart';
import 'package:onepub/src/version/version.g.dart';
import 'package:test/test.dart';

import '../test_settings.dart';
import 'test_utils.dart';

void main() {
  test('onepub import --file', () async {
    await withFile('import --file', 'onepub.token.yaml');
  });

  test('onepub import --file afile.yaml', () async {
    withTempFile((onepubTokenFile) {
      withFile('import --file $onepubTokenFile', onepubTokenFile);
    });
  });
}

Future<void> withFile(String command, String pathToImportFile) async {
  await withTestSettings((testSettings) {
    final onepubToken = testSettings.onepubToken;
    final settings = OnePubSettings.use;
    final organisationName = settings.organisationName;

    pathToImportFile.write('''
  # SettingsYaml settings file
  onepubToken: "$onepubToken"
  ''');
    final clean = runCmd(command);

    // check the cli output from the import command.
    final first = clean.first;
    expect(first, 'OnePub version: $packageVersion ');

    expect(
        clean.contains('Successfully logged into $organisationName.'), isTrue);
  });
}
