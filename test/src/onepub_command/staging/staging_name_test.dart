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

  test('cleanup command binds both organisation ID and name', () {
    final provisioned = ProvisionedTestOrganisation(
      onepubUrl: 'http://localhost:8080',
      organisationName: 'onepub_staging_test_20261103_a',
      organisationId: 'abc-123',
      operatorEmail: 'test@example.com',
      onepubToken: 'synthetic-test-value',
      plan: 'free',
    );
    expect(
      testOrganisationCloseCommand(provisioned),
      'test/organisation/close/abc-123'
      '?name=onepub_staging_test_20261103_a',
    );
  });
}
