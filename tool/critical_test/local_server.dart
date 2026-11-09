import 'dart:io';

import 'package:dcli/posix.dart' show chmod;
import 'package:path/path.dart' as p;

String get _root => Directory.current.path;
Directory get _state =>
    Directory(p.join(_root, '.dart_tool', 'critical_test_server'));

Future<void> startLocalServer() async {
  final state = _state;
  if (state.existsSync()) {
    throw StateError(
      '''
A critical_test server is already active. Run the post-hook to stop it first.''',
    );
  }
  if (await state.parent.resolveSymbolicLinks() != state.parent.absolute.path) {
    throw StateError(
      'Critical-test metadata must not traverse symbolic links.',
    );
  }
  state.createSync(recursive: true);
  chmod(state.path, permission: '700');
  final deploy = p.normalize(
    Platform.environment['ONEPUB_DEPLOY_TEST_REPOSITORY'] ??
        p.join(_root, '..', 'onepub-deploy'),
  );
  try {
    final process = await Process.start(
      p.join(deploy, 'tool', 'serve_cli_test_fixture.dart'),
      [deploy, _root, state.path],
      workingDirectory: deploy,
      mode: ProcessStartMode.detached,
    );
    final deadline = DateTime.now().add(const Duration(minutes: 10));
    while (!File(p.join(state.path, 'ready')).existsSync()) {
      if (Platform.isLinux && !Directory('/proc/${process.pid}').existsSync()) {
        File(p.join(state.path, 'failed'))
            .writeAsStringSync('Fixture process exited.');
      }
      if (File(p.join(state.path, 'failed')).existsSync() ||
          DateTime.now().isAfter(deadline)) {
        final failure = File(p.join(state.path, 'failed'));
        final marker = failure.existsSync() ? failure.readAsStringSync() : '';
        const phases = {
          'host-start',
          'settings',
          'stack-create',
          'database-start',
          'database-plan',
          'server-start',
          'server-ready',
          'member-bootstrap',
          'identity-settings',
          'oauth-bootstrap',
          'broker-start',
        };
        final phase = marker.startsWith('fixture-phase:')
            ? marker.substring('fixture-phase:'.length)
            : 'host-start';
        stderr.writeln(
          'fixture-phase:${phases.contains(phase) ? phase : 'host-start'}',
        );
        throw StateError('The local Docker test server failed to start.');
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  } catch (_) {
    await stopLocalServer();
    rethrow;
  }
}

Future<void> stopLocalServer() async {
  final state = _state;
  if (!state.existsSync()) {
    return;
  }
  File(p.join(state.path, 'stop')).writeAsStringSync('stop');
  final deadline = DateTime.now().add(const Duration(minutes: 3));
  while (!File(p.join(state.path, 'done')).existsSync() &&
      !File(p.join(state.path, 'failed')).existsSync()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('''
Timed out stopping the local test server; state retained at ${state.path}.''');
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  state.deleteSync(recursive: true);
}
