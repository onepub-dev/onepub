import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'native_sources.dart';

/// CryptoKit uses an encrypted, device-bound key reference without requiring
/// keychain entitlements on the Dart executable. Setup is permitted only when
/// creating a key during explicit enrollment, never when opening or signing.
class SecureEnclaveKey {
  Future<Uint8List> operate(
      String operation, String referencePath, List<int>? message) async {
    final sourceHash =
        sha256.convert(utf8.encode(secureEnclaveSource)).toString();
    final home = Platform.environment['HOME'];
    if (home == null || !p.isAbsolute(home)) {
      throw StateError(
          'An absolute HOME directory is required for native setup.');
    }
    final root = Directory(
        p.join(home, 'Library', 'Application Support', 'OnePub', 'native'));
    final cache = Directory(p.join(root.path, '$sourceHash-${Abi.current()}'));
    if (operation == 'create') {
      await _setup(root, cache, sourceHash);
    }
    final executable = await _validate(cache, sourceHash);
    final temporary = await Directory.systemTemp.createTemp('onepub-enclave-');
    try {
      final input = File(p.join(temporary.path, 'message'));
      if (message != null) {
        await input.writeAsBytes(message);
      }
      final result =
          await _run(executable.path, [operation, referencePath, input.path]);
      return base64Decode(result.trim());
    } finally {
      await temporary.delete(recursive: true);
    }
  }

  Future<void> _setup(
      Directory root, Directory cache, String sourceHash) async {
    if (cache.existsSync()) {
      try {
        await _validate(cache, sourceHash);
        return;
      } on Object {
        // Explicit enrollment may rebuild its own disposable compiler output.
        // Open/sign never reaches this repair or invokes a compiler.
        await cache.delete(recursive: true);
      }
    }
    await root.create(recursive: true);
    await _run('/bin/chmod', ['700', root.path]);
    final staging = await root.createTemp('build-');
    try {
      final source = File(p.join(staging.path, 'secure_enclave.swift'));
      final executable = File(p.join(staging.path, 'secure-enclave'));
      await source.writeAsString(secureEnclaveSource);
      try {
        await _run('/usr/bin/xcrun',
            ['swiftc', '-O', source.path, '-o', executable.path]);
        await _run(
            '/usr/bin/codesign', ['--force', '--sign', '-', executable.path]);
      } on Object catch (error) {
        throw StateError('macOS device enrollment needs Xcode Command Line '
            'Tools once to build the Secure Enclave helper. Install them with '
            '`xcode-select --install`, then run `onepub login` again. $error');
      }
      final binaryHash =
          sha256.convert(await executable.readAsBytes()).toString();
      await File(p.join(staging.path, 'identity.json')).writeAsString(
          jsonEncode({'source': sourceHash, 'binary': binaryHash}),
          flush: true);
      await _run('/bin/chmod', ['500', executable.path]);
      await _run('/bin/chmod', ['400', p.join(staging.path, 'identity.json')]);
      // Keep the exact reviewable source next to its locally built executable.
      await _run('/bin/chmod', ['400', source.path]);
      if (cache.existsSync()) {
        await _validate(cache, sourceHash);
      } else {
        await staging.rename(cache.path);
      }
    } finally {
      if (staging.existsSync()) {
        await staging.delete(recursive: true);
      }
    }
  }

  Future<File> _validate(Directory cache, String sourceHash) async {
    try {
      final executable = File(p.join(cache.path, 'secure-enclave'));
      final identity = jsonDecode(
              await File(p.join(cache.path, 'identity.json')).readAsString())
          as Map<String, dynamic>;
      final source =
          await File(p.join(cache.path, 'secure_enclave.swift')).readAsBytes();
      if (identity['source'] != sourceHash ||
          sha256.convert(source).toString() != sourceHash ||
          identity['binary'] !=
              sha256.convert(await executable.readAsBytes()).toString()) {
        throw StateError('Native helper identity does not match its build.');
      }
      await _run(
          '/usr/bin/codesign', ['--verify', '--strict', executable.path]);
      return executable;
    } on Object catch (error) {
      throw StateError('Secure Enclave helper is missing or invalid. '
          'Run interactive `onepub login` to set up this CLI version. $error');
    }
  }

  Future<String> _run(String executable, List<String> arguments) async {
    final result = await Process.run(executable, arguments,
        workingDirectory: Directory.systemTemp.path,
        environment: const {'PATH': '/usr/bin:/bin'});
    if (result.exitCode != 0) {
      throw StateError('${p.basename(executable)} failed: '
          '${result.stderr.toString().trim()}');
    }
    return result.stdout as String;
  }
}
