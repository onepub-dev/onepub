@Tags(['onepub_command', 'integration', 'staging'])
library;

import 'package:test/test.dart';

import 'run_onepub_doctor.dart';
import 'staging_common.dart';

void main() {
  final config = StagingConfig.fromEnv();

  test('onepub doctor', () async {
    await runOnepubDoctor();
  }, timeout: const Timeout(Duration(minutes: 5)), skip: config.skipDoctor);
}
