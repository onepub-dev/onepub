#! /usr/bin/env dcli

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:dcli/posix.dart' as dcli;
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

import 'beta_ready_watch.dart' as readiness;

/// One entry point for repeatable beta assessments. Never schedules a run.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addOption('output', help: 'New directory for private run evidence.')
    ..addOption('version', help: 'Require this exact deployed version.')
    ..addFlag('packages',
        negatable: false,
        help: 'Include disposable archive tests; requires activation.')
    ..addFlag('stress',
        negatable: false,
        help: 'End with 1,000 homepage requests at concurrency 10.');
  final options = parser.parse(arguments);
  if (options['help'] as bool) {
    print('Usage: ./tool/beta_assessment.dart --output=NEW_DIRECTORY '
        '[--version=X.Y.Z] [--packages] [--stress]\n${parser.usage}\n'
        'Target: https://beta.onepub.dev. No redirects to other hosts.\n'
        'Exit: 0 selected checks passed; 2 review needed; '
        '3 blocked or incomplete. See report.json for coverage limits.');
    return;
  }
  final output = options['output'] as String?;
  if (output == null || output.isEmpty) {
    throw ArgumentError('--output must name a new evidence directory.');
  }
  final expected = options['version'] as String?;
  if (expected != null) {
    Version.parse(expected);
  }
  final directory = Directory(p.absolute(output));
  if (FileSystemEntity.typeSync(directory.path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw ArgumentError('Evidence directory already exists; use a new one.');
  }
  directory.createSync(recursive: true);
  dcli.chmod(directory.path, permission: '700');
  final root = p.dirname(p.dirname(Platform.script.toFilePath()));
  final runId = DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(36);
  final runner = AssessmentRunner(root, directory, runId)..save();
  try {
    final version = await betaVersion();
    runner.version = version;
    if (expected != null && version != expected) {
      throw StateError('Deployed version does not match --version.');
    }
    print('Beta assessment $runId: version $version');
    await runner.run(
        'security', 'beta_pentest.dart', ['--security', '--authenticated']);
    await runner.run('surface', 'beta_surface_paths.dart', []);
    await runner.run('search', 'beta_search_inputs.dart', []);
    await runner.run('lookup', 'beta_injection_inputs.dart', []);
    if (options['packages'] as bool) {
      await runner.packages();
    }
    if (options['stress'] as bool) {
      if (runner.results.any((result) => result['status'] != 'passed')) {
        runner.record('stress', 'blocked',
            detail: 'Earlier checks require review; stress was not run.');
      } else {
        await runner.run('stress', 'beta_pentest.dart',
            ['--stress', '--requests=1000', '--concurrency=10']);
      }
    }
    if (await betaVersion() != version) {
      runner.record('postflight', 'blocked',
          detail: 'Deployed version changed during the assessment.');
    } else {
      runner.record('postflight', 'passed');
    }
  } catch (error) {
    // Exception text may contain credentials. Keep only the type.
    runner.record('assessment', 'blocked', detail: '${error.runtimeType}');
  } finally {
    runner
      ..finished = DateTime.now().toUtc().toIso8601String()
      ..save();
    exitCode = assessmentExitCode(runner.results);
    print('Report: ${p.join(directory.path, 'report.json')} (exit $exitCode)');
  }
}

int assessmentExitCode(List<Map<String, Object?>> results) {
  if (results.any((result) => result['status'] == 'blocked')) {
    return 3;
  }
  return results.any((result) => result['status'] != 'passed') ? 2 : 0;
}

Future<String> betaVersion() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final response = await readiness.check(client, '/api/status');
    final version = response.statusCode == 200
        ? readiness.versionFromStatus(response.body)
        : null;
    if (version == null) {
      throw StateError('Beta status unavailable.');
    }
    return version.toString();
  } finally {
    client.close(force: true);
  }
}

class AssessmentRunner {
  AssessmentRunner(this.root, this.directory, this.runId,
      {this.timeout = const Duration(minutes: 10)});

  final String root;
  final Directory directory;
  final String runId;
  final Duration timeout;
  final String started = DateTime.now().toUtc().toIso8601String();
  final results = <Map<String, Object?>>[];
  String? version;
  String? finished;

  void record(String name, String status, {String? detail, int? code}) {
    results.add({
      'case': name,
      'status': status,
      'exitCode': code,
      'detail': detail,
      'time': DateTime.now().toUtc().toIso8601String(),
    });
    save();
    print('$name: $status');
  }

  void save() {
    final temporary = File(p.join(directory.path, 'report.json.tmp'))
      ..writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert({
            'schemaVersion': 1,
            'target': 'https://beta.onepub.dev',
            'runId': runId,
            'version': version,
            'started': started,
            'finished': finished,
            'results': results,
            'coverageLimits': [
              'Only listed cases ran; this is not a complete security audit.',
              'Organisation/role/token suites await cleanup and SCIM adaptation.',
              'Browser, XSS, payment and JWKS tests need separate fixtures.',
              'HTTP search responses do not establish search result isolation.',
            ],
          }),
          flush: true);
    dcli.chmod(temporary.path, permission: '600');
    temporary.renameSync(p.join(directory.path, 'report.json'));
  }

  Future<bool> run(String name, String script, List<String> arguments) async {
    final log = File(p.join(directory.path, '$name.log'))..createSync();
    dcli.chmod(log.path, permission: '600');
    final sink = log.openWrite();
    Process? process;
    StreamSubscription<List<int>>? outputSubscription;
    StreamSubscription<List<int>>? errorSubscription;
    try {
      process = await Process.start(
          'setsid', [p.join(root, 'tool', script), ...arguments],
          workingDirectory: root,
          environment: {'ONEPUB_PENTEST_RUN_ID': runId});
      // Drain both streams while retaining bounded logs.
      var retained = 0;
      void capture(List<int> bytes) {
        final available = 1024 * 1024 - retained;
        if (available > 0) {
          final portion = bytes.take(available).toList();
          sink.add(portion);
          retained += portion.length;
        }
      }

      final stdoutDone = Completer<void>();
      final stderrDone = Completer<void>();
      outputSubscription = process.stdout.listen(capture,
          onDone: stdoutDone.complete, onError: stdoutDone.completeError);
      errorSubscription = process.stderr.listen(capture,
          onDone: stderrDone.complete, onError: stderrDone.completeError);
      final code = await process.exitCode.timeout(timeout);
      await Future.wait([stdoutDone.future, stderrDone.future])
          .timeout(const Duration(seconds: 10));
      record(name, code == 0 ? 'passed' : (code == 2 ? 'review' : 'blocked'),
          code: code, detail: '$name.log');
      return code == 0;
    } catch (error) {
      if (process != null) {
        // Kill the group, including any DCli compiler/runner descendants,
        // before attempting recovery cleanup in the parent.
        await Process.run('/bin/kill', ['-KILL', '--', '-${process.pid}']);
        process.kill(ProcessSignal.sigkill);
        await process.exitCode;
      }
      record(name, 'blocked', detail: '${error.runtimeType}; $name.log');
      return false;
    } finally {
      await outputSubscription?.cancel();
      await errorSubscription?.cancel();
      await sink.close();
    }
  }

  Future<void> packages() async {
    if (!await run('activation', 'beta_ready_watch.dart',
        ['--version=$version', '--minutes=1', '--interval-seconds=15'])) {
      record('packages', 'blocked', detail: 'Test activation unavailable.');
      return;
    }
    for (final fixture in [
      'traversal',
      'symlink',
      'duplicate_pubspec',
      'oversized_readme'
    ]) {
      final package = 'onepub_staging_test_${runId}_$fixture';
      final fixtures = p.join(directory.path, fixture);
      if (!await run('generate_$fixture', 'beta_archive_fixtures.dart',
          ['--output=$fixtures', '--package=$package'])) {
        return;
      }
      // Persist recovery identity before any network mutation.
      record('fixture_$fixture', 'passed', detail: 'package=$package');
      var cleaned = false;
      try {
        await run('archive_$fixture', 'beta_archive_upload.dart', [
          '--file=${p.join(fixtures, '$fixture.tar.gz')}',
          '--package=$package',
          '--expect=reject'
        ]);
      } finally {
        // The uploader also cleans up; this recovers child failure/timeouts.
        cleaned = await run('cleanup_$fixture', 'beta_archive_upload.dart',
            ['--cleanup-only', '--package=$package']);
      }
      if (!cleaned) {
        record('packages', 'blocked',
            detail: 'Cleanup incomplete for $package; stop and recover.');
        return;
      }
    }
  }
}
