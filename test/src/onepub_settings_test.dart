import 'dart:io';

import 'package:dcli_core/dcli_core.dart';
import 'package:onepub/src/exceptions.dart';
import 'package:onepub/src/onepub_settings.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('reports the settings path when YAML is malformed', () async {
    await withTempDirAsync((tempDir) async {
      final settingsFile = File(
        p.join(tempDir, OnePubSettings.defaultSettingsFilename),
      )..writeAsStringSync('onepubUrl: "https://beta.onepub.dev"`\n');

      expect(
        () => OnePubSettings(pathToSettings: settingsFile.path),
        throwsA(
          isA<ExitException>()
              .having((error) => error.exitCode, 'exitCode', 1)
              .having(
                (error) => error.message,
                'message',
                allOf(
                  contains(settingsFile.path),
                  contains('Fix the YAML syntax'),
                ),
              ),
        ),
      );
    });
  });

  test('withPathTo saves only the scoped settings file', () async {
    await withTempDirAsync((defaultDir) async {
      await withTempDirAsync((tempDir) async {
        await withEnvironment(() async {
          final defaultSettingsFile = File(
            p.join(defaultDir, OnePubSettings.defaultSettingsFilename),
          )..writeAsStringSync('onepubUrl: "https://onepub.dev"\n');
          final originalDefaultSettings =
              defaultSettingsFile.readAsStringSync();
          final scopedDir = p.join(tempDir, 'scoped');
          final scopedSettingsFile = File(
            p.join(scopedDir, OnePubSettings.defaultSettingsFilename),
          );

          await OnePubSettings.withPathTo<void>(scopedDir, () async {
            final settings = OnePubSettings.use()
              ..onepubUrl = 'https://squarephone.biz'
              ..organisationName = 'Scoped Org'
              ..obfuscatedOrganisationId = 'scoped-org';
            await settings.save();

            expect(settings.pathToSettings, scopedSettingsFile.path);
          });

          expect(
            defaultSettingsFile.readAsStringSync(),
            originalDefaultSettings,
          );
          expect(scopedSettingsFile.existsSync(), isTrue);
          expect(
            scopedSettingsFile.readAsStringSync(),
            contains('onepubUrl: "https://squarephone.biz"'),
          );
        }, environment: {OnePubSettings.onepubPathEnvKey: defaultDir});
      });
    });
  });
}
