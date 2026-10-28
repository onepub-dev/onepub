@Tags(['onepub_command', 'integration', 'staging'])
library;

import 'package:onepub/src/util/send_command.dart';
import 'package:test/test.dart';

import 'cleanup_package.dart';
import 'pub_archive_checks.dart';
import 'pub_get_test_package.dart';
import 'pub_metadata_checks.dart';
import 'shared_publish_fixture.dart';
import 'staging_common.dart';

void main() {
  final config = StagingConfig.fromEnv();
  final fixture = SharedPublishFixture<PublishedPackage>();
  final selection = publishJourneySelection(
      skipPublish: config.skipPublish,
      skipMetadata: config.skipMetadataTest,
      skipArchive: config.skipArchiveTest,
      skipPubGet: config.skipPubGet,
      skipCleanup: config.skipCleanup);
  // Each assertion can be selected alone or run in shuffled order. Creation is
  // lazy and deletion invalidates the fixture; no test depends on another test.
  Future<void> withPublished(
          Future<void> Function(StagingContext, PublishedPackage) action) =>
      withSuiteAdministrator(config, (context) async {
        final published =
            await fixture.get(() => publishAndVerify(context, config));
        await action(context, published);
      });

  test('publish package', () async {
    await withPublished((context, published) async {});
  },
      timeout: const Timeout(Duration(minutes: 10)),
      skip: !selection['publish package']!);

  test(
      'pub metadata',
      () => withPublished((context, published) => pubMetadataTest(
          versionsBody: published.versionsBody,
          packageName: published.name,
          version: published.version)),
      timeout: const Timeout(Duration(minutes: 10)),
      skip: !selection['pub metadata']!);

  test(
      'pub archive',
      () => withPublished((context, published) => pubArchiveTest(
          versionEntry: published.versionsBody.versions
              .firstWhere((entry) => entry.version == published.version),
          packageName: published.name,
          version: published.version)),
      timeout: const Timeout(Duration(minutes: 15)),
      skip: !selection['pub archive']!);

  test(
      'pub get',
      () => withPublished((context, published) =>
          pubGetTestPackage(published.name, published.version, context.apiUrl)),
      timeout: const Timeout(Duration(minutes: 10)),
      skip: !selection['pub get']!);

  test(
      'cleanup package',
      () => withPublished((context, published) async {
            await cleanupPackage(published.name);
            final response = await sendCommand(
                command:
                    '${context.settings.obfuscatedOrganisationId}/api/packages/${published.name}',
                commandType: CommandType.pub);
            expect(response.status, 404,
                reason: 'Deleted package metadata must no longer be available');
            fixture.deleted();
          }),
      timeout: const Timeout(Duration(minutes: 10)),
      skip: !selection['cleanup package']!);
}
