@Tags(['onepub_command', 'integration', 'staging'])
library;

import 'package:test/test.dart';

import 'staging_common.dart';

void main() {
  final config = StagingConfig.fromEnv();
  setUpAll(() => ensureTestUsers(config));

  test('publish package', () async {
    await withSuiteAdministrator(config, (context) async {
      await publishAndVerify(context, config);
    });
  }, timeout: const Timeout(Duration(minutes: 10)), skip: config.skipPublish);
}
