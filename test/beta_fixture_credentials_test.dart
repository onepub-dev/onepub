import 'package:test/test.dart';

import '../tool/beta_fixture_credentials.dart';

void main() {
  test('issues an assessment pair without exposing credentials on failure',
      () async {
    const secret = 'synthetic-private-canary';
    const token = 'synthetic-cli-token';
    const refresh = 'synthetic-refresh-token';
    final calls = <String>[];
    final result = await issueBetaAssessmentCredentials(
      'https://beta.onepub.dev',
      'onepub_staging_test_rehearsal',
      readSecret: () async => secret,
      exchange: (path, fields) async {
        calls.add(path);
        if (path.endsWith('/token')) {
          expect(fields['client_secret'], secret);
          return {'access_token': 'synthetic-access', 'scope': 'test:fixtures'};
        }
        expect(fields['access_token'], 'synthetic-access');
        return {
          'organisationName': 'onepub_staging_test_rehearsal',
          'onepubToken': token,
          'testFixtureRefreshToken': refresh,
          'testFixtureScopes': 'test:fixtures',
        };
      },
    );
    expect(calls, [
      '/api/provisioning/oauth/token',
      '/api/scim/v2/TestOrganisations',
    ]);
    expect(result['onepubToken'], token);
    expect(result['refreshToken'], refresh);
    await expectLater(
      issueBetaAssessmentCredentials(
        'https://beta.onepub.dev',
        'onepub_staging_test_rehearsal',
        readSecret: () async => secret,
        exchange: (_, __) async => throw StateError(secret),
      ),
      throwsA(isA<StateError>().having((failure) => failure.toString(),
          'safe message', isNot(contains(secret)))),
    );
  });
}
