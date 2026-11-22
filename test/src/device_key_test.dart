import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:onepub/src/device/device_key.dart';
import 'package:pointycastle/export.dart';
import 'package:test/test.dart';

void main() {
  test('public JWK encodes fixed-width coordinates without padding', () {
    final point = [4, ...List.generate(64, (i) => i)];
    final jwk = publicJwkFromPoint(point);
    expect(jwk.keys, unorderedEquals(['kty', 'crv', 'x', 'y']));
    expect(jwk['kty'], 'EC');
    expect(jwk['crv'], 'P-256');
    expect(base64Url.decode(base64Url.normalize(jwk['x'] as String)),
        point.sublist(1, 33));
    expect(base64Url.decode(base64Url.normalize(jwk['y'] as String)),
        point.sublist(33));
    expect((jwk['x'] as String).contains('='), isFalse);
    expect(() => jwk['x'] = 'changed', throwsUnsupportedError);
  });

  test('public JWK rejects compressed, missing, and oversized points', () {
    for (final point in <List<int>>[
      [],
      [2, ...List.filled(32, 1)],
      [4, ...List.filled(63, 0)],
      [4, ...List.filled(65, 0)],
    ]) {
      expect(
          () => publicJwkFromPoint(point), throwsA(isA<DeviceKeyException>()));
    }
  });

  test('TPM signature conversion pads R/S to JOSE widths', () {
    final signature =
        joseSignatureFromTpm([0, 0x18, 0, 0x0b, 0, 1, 0x80, 0, 2, 0x12, 0x34]);
    expect(signature.length, 64);
    expect(signature.sublist(0, 31), everyElement(0));
    expect(signature[31], 0x80);
    expect(signature.sublist(32, 62), everyElement(0));
    expect(signature.sublist(62), [0x12, 0x34]);
  });

  test('TPM signature conversion rejects malformed and other algorithms', () {
    for (final signature in <List<int>>[
      [],
      [0, 0x14, 0, 0x0b],
      [0, 0x18, 0, 4],
      [0, 0x18, 0, 0x0b, 0, 0],
      [0, 0x18, 0, 0x0b, 0, 33, ...List.filled(33, 1)],
      [0, 0x18, 0, 0x0b, 0, 2, 1],
      [0, 0x18, 0, 0x0b, 0, 1, 1, 0, 1, 1, 0],
    ]) {
      expect(() => joseSignatureFromTpm(signature),
          throwsA(isA<DeviceKeyException>()));
    }
  });

  test('open missing hardware reference fails without creating a software key',
      () async {
    final directory = await Directory.systemTemp.createTemp('onepub-key-test-');
    try {
      await expectLater(
          DeviceKey.open(directory), throwsA(isA<DeviceKeyException>()));
      expect(directory.listSync(), isEmpty);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('Linux without physical TPM fails closed', () async {
    final directory = await Directory.systemTemp.createTemp('onepub-key-test-');
    try {
      await expectLater(
          DeviceKey.create(directory),
          throwsA(isA<DeviceKeyException>()
              .having((e) => e.message, 'message', contains('/dev/tpmrm0'))));
      expect(directory.listSync(), isEmpty);
    } finally {
      await directory.delete(recursive: true);
    }
  }, skip: !Platform.isLinux || File('/dev/tpmrm0').existsSync());

  // Explicit hardware coverage: never substitute software keys or emulators.
  // Run on a host with TPM/Secure Enclave and native prerequisites.
  test('native hardware key persists, signs, and deletes', () async {
    final directory =
        await Directory.systemTemp.createTemp('onepub-key-hardware-');
    DeviceKey? key;
    try {
      key = await DeviceKey.create(directory);
      final reopened = await DeviceKey.open(directory);
      expect(reopened.reference, key.reference);
      expect(reopened.publicJwk, key.publicJwk);
      final signature =
          await reopened.sign(utf8.encode('OnePub hardware proof'));
      expect(signature.length, 64);
      await verifySignature(
          reopened, utf8.encode('OnePub hardware proof'), signature);
      await expectLater(
          DeviceKey.create(directory), throwsA(isA<DeviceKeyException>()));
      await key.delete();
      key = null;
      await expectLater(
          DeviceKey.open(directory), throwsA(isA<DeviceKeyException>()));
    } finally {
      await key?.delete();
      await directory.delete(recursive: true);
    }
  },
      skip: Platform.environment['ONEPUB_TEST_HARDWARE_DEVICE_KEY'] != '1',
      timeout: const Timeout(Duration(minutes: 2)));
  test('TPM simulator creates a persistent key and verifiable signatures',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('onepub-key-simulator-');
    final backend = LinuxTpmBackend.forTesting(
        tcti: Platform.environment['ONEPUB_TEST_TPM_TCTI']!,
        toolsDirectory:
            Platform.environment['ONEPUB_TEST_TPM_TOOLS'] ?? '/usr/bin');
    DeviceKey? key;
    try {
      key = await DeviceKey.create(directory, linuxBackend: backend);
      final reopened = await DeviceKey.open(directory, linuxBackend: backend);
      expect(reopened.publicJwk, key.publicJwk);
      for (final message in [<int>[], utf8.encode('OnePub simulator proof')]) {
        await verifySignature(reopened, message, await reopened.sign(message));
      }
      final metadata = File('${directory.path}/key.json');
      final saved =
          jsonDecode(await metadata.readAsString()) as Map<String, dynamic>;
      (saved['publicJwk'] as Map<String, dynamic>)['x'] = 'wrong';
      await metadata.writeAsString(jsonEncode(saved));
      await expectLater(DeviceKey.open(directory, linuxBackend: backend),
          throwsA(isA<DeviceKeyException>()));
    } finally {
      await key?.delete();
      await directory.delete(recursive: true);
    }
  },
      skip: !Platform.isLinux ||
          !Platform.environment.containsKey('ONEPUB_TEST_TPM_TCTI'),
      timeout: const Timeout(Duration(minutes: 2)));
}

Future<void> verifySignature(
    DeviceKey key, List<int> message, List<int> bytes) async {
  final jwk = key.publicJwk;
  BigInt integer(List<int> encoded) => BigInt.parse(
      encoded.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(),
      radix: 16);
  final curve = ECCurve_secp256r1();
  final point = curve.curve.createPoint(
      integer(base64Url.decode(base64Url.normalize(jwk['x'] as String))),
      integer(base64Url.decode(base64Url.normalize(jwk['y'] as String))));
  final verifier = ECDSASigner(SHA256Digest())
    ..init(false, PublicKeyParameter<ECPublicKey>(ECPublicKey(point, curve)));
  final signature =
      ECSignature(integer(bytes.sublist(0, 32)), integer(bytes.sublist(32)));
  expect(
      verifier.verifySignature(Uint8List.fromList(message), signature), isTrue);
  expect(
      verifier.verifySignature(Uint8List.fromList([...message, 0]), signature),
      isFalse);
}
