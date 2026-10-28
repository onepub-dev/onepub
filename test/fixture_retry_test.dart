import 'package:test/test.dart';

import 'fixture_retry.dart';

void main() {
  test('only definitive member absence permits fixture creation', () {
    expect(
        isAbsentFixtureMember(
            'person@example.test does not exist in Organisation Test.'),
        isTrue);
    expect(isAbsentFixtureMember('Member not found'), isTrue);
    for (final message in [
      'Forbidden',
      'The organisation was not found.',
      'Too many requests',
      'Service unavailable'
    ]) {
      expect(isAbsentFixtureMember(message), isFalse);
    }
  });
  for (final failure in ['Member not found', 'Forbidden', 'already exists']) {
    test('$failure returns immediately to the fixture state machine', () async {
      var calls = 0;
      final result = await retryFixture(
          () async {
            calls++;
            return failure;
          },
          shouldRetry: isTransientFixtureFailure,
          delay: (_) {
            fail('Permanent outcomes must not wait');
          });
      expect(result, failure);
      expect(calls, 1);
    });
  }
  for (final failure in [
    'Too many requests',
    'Service unavailable',
    'Empty response'
  ]) {
    test('$failure retries within the bound', () async {
      var calls = 0;
      final delays = <Duration>[];
      final result = await retryFixture(
          () async {
            calls++;
            return calls < 3 ? failure : 'success';
          },
          shouldRetry: isTransientFixtureFailure,
          delay: (value) async {
            delays.add(value);
          });
      expect(result, 'success');
      expect(calls, 3);
      expect(delays,
          [const Duration(milliseconds: 1500), const Duration(seconds: 3)]);
    });
  }
  test('persistent transient failures exhaust exactly the configured attempts',
      () async {
    var calls = 0;
    await retryFixture(() async {
      calls++;
      return 'rate limit';
    },
        shouldRetry: isTransientFixtureFailure,
        attempts: 2,
        delay: (_) async {});
    expect(calls, 2);
  });
}
