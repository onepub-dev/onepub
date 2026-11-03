import 'package:test/test.dart';

import 'staging_common.dart';

void main() {
  test('disposable organisation names identify each recurring run', () {
    expect(
      stagingTestOrganisationName('free', 12345, '20261103_a'),
      'onepub_staging_test_download_limit_free_20261103_a_12345',
    );
    expect(
      stagingTestOrganisationName('free', 12345, null),
      'onepub_staging_test_download_limit_free_12345',
    );
    expect(
      () => stagingTestOrganisationName('free', 12345, 'invalid/directory'),
      throwsArgumentError,
    );
  });
}
