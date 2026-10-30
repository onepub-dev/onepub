import 'dart:io';

import 'package:path/path.dart' as p;

String get _root => Directory.current.path;
Directory get _state =>
    Directory(p.join(_root, '.dart_tool', 'critical_test_server'));

Future<void> startLocalServer() async {
  final state = _state;
  if (state.existsSync()) {
    throw StateError('''
A critical_test server is already active. Run the post-hook to stop it first.''');
  }
  state.createSync(recursive: true);
  final deploy = p.normalize(p.join(_root, '..', 'onepub-deploy'));
  try {
    final process = await Process.start(
        Platform.resolvedExecutable,
        [
          '--packages=$deploy/.dart_tool/package_config.json',
          p.join(_root, 'tool', 'critical_test', 'fixture_host.dart'),
          deploy,
          state.path,
        ],
        mode: ProcessStartMode.detached);
    final deadline = DateTime.now().add(const Duration(minutes: 10));
    while (!File(p.join(state.path, 'ready')).existsSync()) {
      if (Platform.isLinux && !Directory('/proc/${process.pid}').existsSync()) {
        File(p.join(state.path, 'failed'))
            .writeAsStringSync('Fixture process exited.');
      }
      if (File(p.join(state.path, 'failed')).existsSync() ||
          DateTime.now().isAfter(deadline)) {
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
      throw StateError(
          '''
Timed out stopping the local test server; state retained at ${state.path}.''');
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  state.deleteSync(recursive: true);
}
