import 'package:test/test.dart';

import 'test_settings.dart';

void main() {
  group('assertSafeOnePubTestUrl', () {
    test('allows approved staging hosts', () {
      expect(
        assertSafeOnePubTestUrl(
          'https://beta.onepub.dev',
          source: 'test',
        ),
        'https://beta.onepub.dev',
      );
      expect(
        assertSafeOnePubTestUrl(
          'https://staging.onepub.dev',
          source: 'test',
        ),
        'https://staging.onepub.dev',
      );
    });

    test('allows local development hosts', () {
      expect(
        assertSafeOnePubTestUrl(
          'http://localhost:8080',
          source: 'test',
        ),
        'http://localhost:8080',
      );
      expect(
        assertSafeOnePubTestUrl(
          'http://192.168.1.20:8080',
          source: 'test',
        ),
        'http://192.168.1.20:8080',
      );
    });

    test('rejects production onepub', () {
      expect(
        () => assertSafeOnePubTestUrl(
          'https://onepub.dev',
          source: 'test',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
