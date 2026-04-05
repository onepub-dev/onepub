@Tags(['onepub_command', 'integration', 'staging'])
library;

import 'dart:async';
import 'dart:io';

import 'package:dcli/dcli.dart';
import 'package:onepub/src/util/send_command.dart';
import 'package:test/test.dart';

import 'staging_common.dart';

class RateLimitResult {
  final Map<int, int> counts;
  final int elapsedMilliseconds;

  RateLimitResult(this.counts, this.elapsedMilliseconds);

  int get tooMany => counts[429] ?? 0;
}

Future<RateLimitResult> rateLimitTest(String command, int totalRequests) async {
  stdout.writeln('Running rate-limit burst: $totalRequests requests');

  final stopwatch = Stopwatch()..start();
  final futures = List<Future<int>>.generate(totalRequests, (_) async {
    try {
      final response = await sendCommand(
        command: command,
        commandType: CommandType.cli,
      );
      return response.status;
    } catch (_) {
      return 0;
    }
  });

  final statuses = await Future.wait(futures);
  stopwatch.stop();

  final counts = <int, int>{};
  for (final status in statuses) {
    counts[status] = (counts[status] ?? 0) + 1;
  }

  final result = RateLimitResult(counts, stopwatch.elapsedMilliseconds);
  stdout.writeln(
      'Rate-limit results in ${result.elapsedMilliseconds}ms: $counts');
  if ((counts[429] ?? 0) == 0) {
    stderr.writeln(
        'No 429 responses detected; increase --rate-requests if needed.');
  }

  return result;
}

Future<void> rateLimitRecoveryTest(String command,
    {Duration wait = const Duration(seconds: 6)}) async {
  stdout.writeln(
      'Waiting ${wait.inSeconds}s before rate-limit recovery check...');
  await sleepAsync(wait.inSeconds);

  final response = await sendCommand(
    command: command,
    commandType: CommandType.cli,
  );

  if (response.status == 429) {
    throw StateError('Rate-limit recovery failed: still receiving 429.');
  }
}

void main() {
  final config = StagingConfig.fromEnv();
  setUpAll(() => ensureTestUsers(config));

  test('rate limit burst', () async {
    await withAdmin(config, (_) async {
      final result = await rateLimitTest(config.rateRoute, config.rateRequests);
      if (result.tooMany == 0) {
        throw StateError('Rate-limit test did not produce any 429 responses.');
      }
    });
  }, timeout: const Timeout(Duration(minutes: 5)), skip: config.skipRateLimit);

  test('rate limit recovery', () async {
    await withAdmin(config, (_) async {
      await rateLimitRecoveryTest(config.rateRoute);
    });
  },
      timeout: const Timeout(Duration(minutes: 5)),
      skip: config.skipRateLimitRecovery);
}
