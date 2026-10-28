import 'dart:async';

bool isAbsentFixtureMember(String? message) {
  final value = (message ?? '').toLowerCase();
  return value.contains('does not exist in organisation') ||
      value == 'member not found';
}

/// Unknown failures and permission denials are never retried. An absent
/// member is a normal result for a new, uniquely named fixture.
bool isTransientFixtureFailure(String? message) {
  final value = (message ?? '').trim().toLowerCase();
  return value.isEmpty ||
      value == 'empty response' ||
      value.contains('too many cli requests') ||
      value.contains('too many requests') ||
      value.contains('rate limit') ||
      value.contains('temporarily unavailable') ||
      value.contains('service unavailable') ||
      value.contains('gateway timeout');
}

Future<T> retryFixture<T>(
  Future<T> Function() operation, {
  required bool Function(T) shouldRetry,
  int attempts = 5,
  Future<void> Function(Duration) delay = Future<void>.delayed,
}) async {
  if (attempts < 1) {
    throw ArgumentError.value(attempts, 'attempts', 'must be positive');
  }
  for (var attempt = 1;; attempt++) {
    final result = await operation();
    if (attempt == attempts || !shouldRetry(result)) {
      return result;
    }
    await delay(Duration(milliseconds: 1500 * attempt));
  }
}
