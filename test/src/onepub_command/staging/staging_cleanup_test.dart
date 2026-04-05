@Tags(['onepub_command', 'integration', 'staging'])
library;

import 'package:test/test.dart';

import 'cleanup_package.dart';
import 'publish_test_package.dart';
import 'staging_common.dart';

void main() {
  final config = StagingConfig.fromEnv();
  setUpAll(() => ensureTestUsers(config));

  test('cleanup package', () async {
    await withAdmin(config, (context) async {
      final publishResult = await publishTestPackage(
        packagePrefix: config.packagePrefix,
        apiUrl: context.apiUrl,
        team: config.team,
        skipPackageCreate: config.skipPackageCreate,
      );
      await cleanupPackage(publishResult.packageName);
    });
  },
      timeout: const Timeout(Duration(minutes: 10)),
      skip: config.skipCleanup || config.skipPublish);
}
