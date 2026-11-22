import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'native_sources.dart';
import 'secure_enclave.dart';

/// A non-exportable P-256 signing key in the local hardware provider.
///
/// This is a local guarantee only, not remote hardware attestation. The public
/// API deliberately supplies no self-reported hardware assurance to a server.
class DeviceKey {
  DeviceKey._(
      this._storage, this.reference, this.publicJwk, this._linuxBackend);

  final Directory _storage;
  final LinuxTpmBackend _linuxBackend;

  /// Opaque local provider reference. It is not a server-side device ID.
  final String reference;
  final Map<String, dynamic> publicJwk;

  static const _metadataName = 'key.json';
  static final _testBackendZoneKey = Object();

  /// Injects an isolated simulator for integration tests, including CLI flows.
  /// Production entrypoints never call this or inspect test environment values.
  static Future<T> withLinuxBackendForTesting<T>(
          LinuxTpmBackend backend, Future<T> Function() body) =>
      runZoned(body, zoneValues: {_testBackendZoneKey: backend});

  static LinuxTpmBackend _resolveBackend(LinuxTpmBackend? explicit) =>
      explicit ??
      Zone.current[_testBackendZoneKey] as LinuxTpmBackend? ??
      const LinuxTpmBackend.hardware();

  static Future<DeviceKey> create(Directory storage,
      {LinuxTpmBackend? linuxBackend}) async {
    final backend = _resolveBackend(linuxBackend);
    await storage.create(recursive: true);
    final metadata = File(p.join(storage.path, _metadataName));
    if (metadata.existsSync()) {
      throw const DeviceKeyException('A device key already exists here.');
    }
    if (!Platform.isWindows) {
      await _run('/bin/chmod', ['700', storage.absolute.path]);
    }
    final key =
        DeviceKey._(storage.absolute, const Uuid().v4(), const {}, backend);
    final point = await key._operate('create');
    final jwk = publicJwkFromPoint(point);
    await metadata.writeAsString(
        jsonEncode({
          'version': 1,
          'platform': Platform.operatingSystem,
          'reference': key.reference,
          'publicJwk': jwk,
        }),
        flush: true);
    return DeviceKey._(storage.absolute, key.reference, jwk, backend);
  }

  static Future<DeviceKey> open(Directory storage,
      {LinuxTpmBackend? linuxBackend}) async {
    final backend = _resolveBackend(linuxBackend);
    try {
      final metadata = jsonDecode(
              await File(p.join(storage.path, _metadataName)).readAsString())
          as Map<String, dynamic>;
      final reference = metadata['reference'] as String;
      if (metadata['version'] != 1 ||
          metadata['platform'] != Platform.operatingSystem ||
          !RegExp(r'^[a-f0-9-]{36}$').hasMatch(reference)) {
        throw const DeviceKeyException(
            'Invalid or incompatible key reference.');
      }
      final saved = metadata['publicJwk'] as Map<String, dynamic>;
      final key = DeviceKey._(storage.absolute, reference, saved, backend);
      final actual = publicJwkFromPoint(await key._operate('open'));
      if (saved['kty'] != actual['kty'] ||
          saved['crv'] != actual['crv'] ||
          saved['x'] != actual['x'] ||
          saved['y'] != actual['y']) {
        throw const DeviceKeyException(
            'Hardware key does not match its registration.');
      }
      return DeviceKey._(storage.absolute, reference, actual, backend);
    } on DeviceKeyException {
      rethrow;
    } on Object catch (error) {
      throw DeviceKeyException('Cannot open local device key: $error');
    }
  }

  /// Signs the original message with SHA-256, returning JOSE R || S (64 bytes).
  Future<Uint8List> sign(List<int> bytes) async {
    final signature = await _operate('sign', bytes);
    if (signature.length != 64) {
      throw const DeviceKeyException(
          'Hardware provider returned an invalid ES256 signature.');
    }
    return signature;
  }

  /// Removes this local key. Server-side revocation is a separate action.
  Future<void> delete() async {
    if (Platform.isWindows) {
      await _operate('delete');
    }
    // Remove backend files only; never recursively delete caller data.
    for (final name in [_metadataName, 'key.blob', 'key.pub', 'key.priv']) {
      final file = File(p.join(_storage.path, name));
      if (file.existsSync()) {
        await file.delete();
      }
    }
  }

  Future<Uint8List> _operate(String operation, [List<int>? message]) async {
    if (Platform.isMacOS) {
      try {
        return await SecureEnclaveKey()
            .operate(operation, p.join(_storage.path, 'key.blob'), message);
      } on Object catch (error) {
        throw DeviceKeyException('Secure Enclave operation failed: $error');
      }
    }
    final scratch = await Directory.systemTemp.createTemp('onepub-device-');
    try {
      final input = File(p.join(scratch.path, 'message'));
      if (message != null) {
        await input.writeAsBytes(message, flush: true);
      }
      if (Platform.isLinux) {
        return await _linux(operation, scratch, input);
      }
      late String output;
      if (Platform.isWindows) {
        final source = File(p.join(scratch.path, 'device.ps1'));
        await source.writeAsString(platformCryptoSource);
        final windows = Platform.environment['SystemRoot'] ?? r'C:\Windows';
        output = await _run(
            p.join(windows, 'System32', 'WindowsPowerShell', 'v1.0',
                'powershell.exe'),
            [
              '-NoLogo',
              '-NoProfile',
              '-NonInteractive',
              '-ExecutionPolicy',
              'Bypass',
              '-File',
              source.path,
              operation,
              'OnePub-$reference',
              input.path,
            ]);
      } else {
        throw const DeviceKeyException(
            'Device keys require Linux TPM2, Windows TPM, '
            'or macOS Secure Enclave.');
      }
      return operation == 'delete' ? Uint8List(0) : base64Decode(output.trim());
    } finally {
      await scratch.delete(recursive: true);
    }
  }

  Future<Uint8List> _linux(
      String operation, Directory scratch, File input) async {
    // Pin a kernel TPM device: never accept simulator/environment TCTIs.
    if (_linuxBackend._requiresHardware && !File('/dev/tpmrm0').existsSync()) {
      throw const DeviceKeyException(
          'A TPM 2.0 resource-manager device (/dev/tpmrm0) is required.');
    }
    final primary = p.join(scratch.path, 'primary.ctx');
    final child = p.join(scratch.path, 'child.ctx');
    final public = p.join(_storage.path, 'key.pub');
    final private = p.join(_storage.path, 'key.priv');
    Future<String> tpm(String name, List<String> args) => _run(
        p.join(_linuxBackend._toolsDirectory, 'tpm2_$name'),
        ['-T', _linuxBackend._tcti, ...args]);
    try {
      await tpm('createprimary',
          ['-C', 'o', '-G', 'ecc', '-g', 'sha256', '-c', primary]);
      if (operation == 'create') {
        await tpm('create', [
          '-C',
          primary,
          '-G',
          'ecc256:ecdsa-sha256',
          '-g',
          'sha256',
          '-a',
          'fixedtpm|fixedparent|sensitivedataorigin|userwithauth|sign',
          '-u',
          public,
          '-r',
          private
        ]);
      }
      await tpm(
          'load', ['-C', primary, '-u', public, '-r', private, '-c', child]);
      final output = p.join(scratch.path, 'output');
      if (operation == 'sign') {
        await tpm('sign', [
          '-c',
          child,
          '-g',
          'sha256',
          '-s',
          'ecdsa',
          '-f',
          'tss',
          '-o',
          output,
          input.path
        ]);
        return joseSignatureFromTpm(await File(output).readAsBytes());
      }
      await tpm('readpublic', ['-c', child, '-f', 'der', '-o', output]);
      final der = await File(output).readAsBytes();
      // DER SubjectPublicKeyInfo for id-ecPublicKey / prime256v1, uncompressed.
      const prefix = [
        0x30,
        0x59,
        0x30,
        0x13,
        0x06,
        0x07,
        0x2a,
        0x86,
        0x48,
        0xce,
        0x3d,
        0x02,
        0x01,
        0x06,
        0x08,
        0x2a,
        0x86,
        0x48,
        0xce,
        0x3d,
        0x03,
        0x01,
        0x07,
        0x03,
        0x42,
        0x00
      ];
      if (der.length != prefix.length + 65 ||
          !List.generate(prefix.length, (i) => der[i] == prefix[i])
              .every((v) => v)) {
        throw const DeviceKeyException(
            'TPM returned an unexpected public key format.');
      }
      return Uint8List.sublistView(der, prefix.length);
    } finally {
      // Never flush other applications' TPM objects or sessions.
      for (final context in [child, primary]) {
        if (File(context).existsSync()) {
          try {
            await tpm('flushcontext', [context]);
          } on DeviceKeyException {
            // The resource manager may already have evicted the saved context.
          }
        }
      }
    }
  }

  static Future<String> _run(String executable, List<String> arguments) async {
    if (!p.isAbsolute(executable)) {
      throw const DeviceKeyException('Native helper path must be absolute.');
    }
    try {
      final result = await Process.run(
        executable,
        arguments,
        workingDirectory: Directory.systemTemp.path,
        environment:
            Platform.isWindows ? null : const {'PATH': '/usr/bin:/bin'},
      );
      if (result.exitCode != 0) {
        throw DeviceKeyException('Hardware device key operation failed '
            '(${p.basename(executable)}): ${result.stderr.toString().trim()}');
      }
      return result.stdout as String;
    } on ProcessException catch (error) {
      throw DeviceKeyException('Hardware device key helper unavailable '
          '(${p.basename(executable)}): ${error.message}');
    }
  }
}

Map<String, dynamic> publicJwkFromPoint(List<int> point) {
  if (point.length != 65 || point.first != 4) {
    throw const DeviceKeyException(
        'Expected an uncompressed P-256 public key.');
  }
  String encode(List<int> value) => base64UrlEncode(value).replaceAll('=', '');
  return Map.unmodifiable({
    'kty': 'EC',
    'crv': 'P-256',
    'x': encode(point.sublist(1, 33)),
    'y': encode(point.sublist(33))
  });
}

/// Decode TPMT_SIGNATURE (ECDSA, SHA256) with checked bounds and fixed-width R/S.
Uint8List joseSignatureFromTpm(List<int> encoded) {
  var offset = 0;
  int read16() {
    if (offset + 2 > encoded.length) {
      throw const DeviceKeyException('Truncated TPM signature.');
    }
    final value = (encoded[offset] << 8) | encoded[offset + 1];
    offset += 2;
    return value;
  }

  if (read16() != 0x18 || read16() != 0x0b) {
    throw const DeviceKeyException('TPM signature is not ECDSA with SHA256.');
  }
  final signature = Uint8List(64);
  for (var component = 0; component < 2; component++) {
    final length = read16();
    if (length < 1 || length > 32 || offset + length > encoded.length) {
      throw const DeviceKeyException('Invalid TPM signature component.');
    }
    signature.setRange(component * 32 + 32 - length, component * 32 + 32,
        encoded.sublist(offset, offset + length));
    offset += length;
  }
  if (offset != encoded.length) {
    throw const DeviceKeyException('Unexpected data after TPM signature.');
  }
  return signature;
}

/// Production always uses the kernel's hardware resource manager. Tests may
/// explicitly inject a separately provisioned simulator/resource-manager TCTI.
/// There is intentionally no environment or command-line transport override.
class LinuxTpmBackend {
  const LinuxTpmBackend.hardware()
      : _tcti = 'device:/dev/tpmrm0',
        _toolsDirectory = '/usr/bin',
        _requiresHardware = true;

  const LinuxTpmBackend.forTesting(
      {required String tcti, String toolsDirectory = '/usr/bin'})
      : _tcti = tcti,
        _toolsDirectory = toolsDirectory,
        _requiresHardware = false;

  final String _tcti;
  final String _toolsDirectory;
  final bool _requiresHardware;
}

class DeviceKeyException implements Exception {
  const DeviceKeyException(this.message);
  final String message;
  @override
  String toString() => message;
}
