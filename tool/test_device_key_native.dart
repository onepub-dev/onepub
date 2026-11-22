#! /usr/bin/env dcli

// Runs the shipped Linux TPM backend against swtpm through a real resource
// manager on an isolated D-Bus session. No system TPM state is read or changed.
import 'dart:async';
import 'dart:io';

import 'package:dcli/dcli.dart';

Future<void> main(List<String> args) async {
  if (args.contains('--help')) {
    print(
        'Usage: ./tool/test_device_key_native.dart [--prefix=/absolute/path]\n'
        'Requires swtpm, tpm2-tools, tpm2-abrmd and libtss2-tcti-tabrmd.\n'
        'Runs only an isolated TPM simulator; no physical TPM is accessed.');
    return;
  }
  final prefixArgument = args.where((arg) => arg.startsWith('--prefix='));
  final prefix =
      prefixArgument.isEmpty ? '' : prefixArgument.single.substring(9);
  if (prefix.isNotEmpty && !prefix.startsWith('/')) {
    throw ArgumentError('The prerequisite prefix must be an absolute path.');
  }
  if (!Platform.isLinux) {
    stderr.writeln(red('This simulator runner requires Linux.'));
    exitCode = 1;
    return;
  }
  if (!args.contains('--inside-dbus')) {
    final session = await Process.start('/usr/bin/dbus-run-session',
        ['--', Platform.script.toFilePath(), ...args, '--inside-dbus'],
        mode: ProcessStartMode.inheritStdio);
    exitCode = await session.exitCode;
    return;
  }
  final temporary = await Directory.systemTemp.createTemp('onepub-tpm-test-');
  final children = <Process>[];
  final outputSubscriptions = <StreamSubscription<List<int>>>[];
  try {
    final port = await reservePortPair();
    Future<Process> start(String executable, List<String> arguments) async {
      final process = await Process.start(executable, arguments);
      children.add(process);
      outputSubscriptions
        ..add(process.stdout.listen(stdout.add))
        ..add(process.stderr.listen(stderr.add));
      return process;
    }

    await start('$prefix/usr/bin/swtpm', [
      'socket',
      '--tpm2',
      '--tpmstate',
      'dir=${temporary.path}',
      '--server',
      'type=tcp,port=$port,bindaddr=127.0.0.1',
      '--ctrl',
      'type=tcp,port=${port + 1},bindaddr=127.0.0.1',
      '--flags',
      'not-need-init,startup-clear',
    ]);
    // The simulator's control socket is ready before the resource manager
    // initializes it. Both services are scoped to this test process/session.
    await waitForSocket(port + 1);
    await start('$prefix/usr/sbin/tpm2-abrmd', [
      '--allow-root',
      '--session',
      '--tcti=swtpm:host=127.0.0.1,port=$port',
    ]);
    const tcti = 'tabrmd:bus_type=session';
    var ready = false;
    for (var attempt = 0; attempt < 100; attempt++) {
      final result = await Process.run(
          '$prefix/usr/bin/tpm2_getcap', ['-T', tcti, 'properties-fixed']);
      if (result.exitCode == 0) {
        ready = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!ready) {
      throw StateError('TPM resource manager did not become ready.');
    }
    final test = await Process.start(
        'dart', ['test', 'test/src/device_key_test.dart'],
        environment: {
          'ONEPUB_TEST_TPM_TCTI': tcti,
          'ONEPUB_TEST_TPM_TOOLS': '$prefix/usr/bin'
        },
        mode: ProcessStartMode.inheritStdio);
    exitCode = await test.exitCode;
  } on Object catch (error) {
    stderr.writeln(red('Native device-key test failed: $error'));
    exitCode = 1;
  } finally {
    for (final process in children.reversed) {
      process.kill();
      await process.exitCode.timeout(const Duration(seconds: 5), onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -1;
      });
    }
    for (final subscription in outputSubscriptions) {
      await subscription.cancel();
    }
    await temporary.delete(recursive: true);
  }
}

Future<int> reservePortPair() async {
  for (var attempt = 0; attempt < 20; attempt++) {
    final first = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    try {
      if (first.port == 65535) {
        continue;
      }
      final second =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, first.port + 1);
      await second.close();
      return first.port;
    } on SocketException {
      // Try a different pair if the adjacent control port is occupied.
    } finally {
      await first.close();
    }
  }
  throw StateError('Cannot reserve simulator TCP ports.');
}

Future<void> waitForSocket(int port) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    try {
      final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
      socket.destroy();
      return;
    } on SocketException {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
  throw StateError('TPM simulator did not become ready.');
}
