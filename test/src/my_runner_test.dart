import 'dart:io';

import 'package:dcli_core/dcli_core.dart';
import 'package:onepub/src/my_runner.dart';
import 'package:onepub/src/onepub_settings.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('--help does not load OnePub settings', () async {
    await withTempDirAsync((tempDir) async {
      File(p.join(tempDir, OnePubSettings.defaultSettingsFilename))
          .writeAsStringSync('onepubUrl: "https://beta.onepub.dev"`\n');

      await withEnvironment(
        () => MyRunner(['--help'], 'onepub', 'OnePub CLI tools.').init(),
        environment: {OnePubSettings.onepubPathEnvKey: tempDir},
      );
    });
  });
}
