import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/beta_assessment.dart';

void main() {
  test('a stalled child is terminated and recorded as incomplete', () async {
    final directory = Directory.systemTemp.createTempSync('beta-timeout-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    Directory('${directory.path}/tool').createSync();
    Link('${directory.path}/tool/stalled').createSync('/bin/sleep');
    final runner = AssessmentRunner(directory.path, directory, 'localtest',
        timeout: const Duration(milliseconds: 100));
    final watch = Stopwatch()..start();
    expect(await runner.run('stalled', 'stalled', ['30']), isFalse);
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    expect(runner.results.single['status'], 'blocked');
  });

  test(
      'failed archive still cleans up and failed cleanup stops further uploads',
      () async {
    final directory = Directory.systemTemp.createTempSync('beta-cleanup-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final runner = FailingArchiveRunner(directory)..version = '5.73.3';
    await runner.packages();
    expect(runner.calls, [
      'activation',
      'generate_traversal',
      'archive_traversal',
      'cleanup_traversal'
    ]);
    expect(assessmentExitCode(runner.results), 3);
  });

  test('incomplete coverage takes precedence over review and passes', () {
    expect(
        assessmentExitCode([
          {'status': 'passed'}
        ]),
        0);
    expect(
        assessmentExitCode([
          {'status': 'review'}
        ]),
        2);
    expect(
        assessmentExitCode([
          {'status': 'review'},
          {'status': 'blocked'}
        ]),
        3);
  });

  test('failed process launch leaves a readable incomplete report', () async {
    final directory = Directory.systemTemp.createTempSync('beta-run-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final runner = AssessmentRunner(directory.path, directory, 'localtest');
    expect(await runner.run('missing', 'absent.dart', []), isFalse);
    final report =
        jsonDecode(File('${directory.path}/report.json').readAsStringSync())
            as Map;
    expect(report['target'], 'https://beta.onepub.dev');
    final result = (report['results'] as List).single as Map;
    expect(result['status'], 'blocked');
    expect(report['coverageLimits'], isNotEmpty);
  });

  test('package fixture work stops when activation cannot run', () async {
    final directory = Directory.systemTemp.createTempSync('beta-gate-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final runner = AssessmentRunner(directory.path, directory, 'localtest')
      ..version = '5.73.3';
    await runner.packages();
    expect(runner.results.map((result) => result['case']),
        ['activation', 'packages']);
    expect(assessmentExitCode(runner.results), 3);
  });
}

class FailingArchiveRunner extends AssessmentRunner {
  FailingArchiveRunner(Directory directory)
      : super(directory.path, directory, 'localtest');

  final calls = <String>[];

  @override
  Future<bool> run(String name, String script, List<String> arguments) async {
    calls.add(name);
    if (name.startsWith('archive_')) {
      final report = File('${directory.path}/report.json').readAsStringSync();
      expect(report, contains('onepub_staging_test_localtest_traversal'));
      return false;
    }
    return !name.startsWith('cleanup_');
  }
}
