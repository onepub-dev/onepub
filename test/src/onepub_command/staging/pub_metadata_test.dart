@Tags(['onepub_command', 'integration', 'staging'])
library;

import 'dart:io';

import 'package:onepub/src/api/versions.dart';
import 'package:test/test.dart';

import 'staging_common.dart';

Future<void> pubMetadataTest({
  required PubVersionsBody versionsBody,
  required String packageName,
  required String version,
}) async {
  stdout.writeln('Checking pub metadata for $packageName...');

  if (versionsBody.latest.version.isEmpty) {
    throw StateError('Pub metadata missing latest version.');
  }

  if (versionsBody.latest.version != version) {
    throw StateError('''
Latest version mismatch: expected $version, got ${versionsBody.latest.version}.''');
  }

  final entry = versionsBody.versions
      .where((candidate) => candidate.version == version)
      .cast<JsonVersion?>()
      .firstWhere((candidate) => candidate != null, orElse: () => null);

  if (entry == null) {
    throw StateError('Published version $version not found in versions list.');
  }

  if (entry.archiveUrl.isEmpty) {
    throw StateError('Archive URL missing for version $version.');
  }

  final pubspec = entry.pubspec;
  if (pubspec.isNotEmpty) {
    final pubspecName = pubspec['name'] as String?;
    final pubspecVersion = pubspec['version'] as String?;
    if (pubspecName != null && pubspecName != packageName) {
      throw StateError(
          'Pubspec name mismatch: expected $packageName, got $pubspecName.');
    }
    if (pubspecVersion != null && pubspecVersion != version) {
      throw StateError(
          'Pubspec version mismatch: expected $version, got $pubspecVersion.');
    }
  }
}

void main() {
  final config = StagingConfig.fromEnv();
  setUpAll(() => ensureTestUsers(config));

  test('pub metadata', () async {
    await withAdmin(config, (context) async {
      final published = await publishAndVerify(context, config);
      await pubMetadataTest(
        versionsBody: published.versionsBody,
        packageName: published.name,
        version: published.version,
      );
    });
  },
      timeout: const Timeout(Duration(minutes: 10)),
      skip: config.skipMetadataTest || config.skipPublish);
}
