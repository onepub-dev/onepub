@Tags(['onepub_command', 'integration', 'staging'])
library;

import 'package:test/test.dart';

import 'pub_get_test_package.dart';
import 'staging_common.dart';

void main() {
  final config = StagingConfig.fromEnv();
  setUpAll(() => ensureTestUsers(config));

  test('pub get', () async {
    await withAdmin(config, (context) async {
      final published = await publishAndVerify(context, config);
      await pubGetTestPackage(
        published.name,
        published.version,
        context.apiUrl,
      );
    });
  },
      timeout: const Timeout(Duration(minutes: 10)),
      skip: config.skipPubGet || config.skipPublish);
}
