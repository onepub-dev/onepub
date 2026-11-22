#! /usr/bin/env dcli

// Portable native backend smoke test, also compiled for disposable test VMs.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dcli/dcli.dart';
import 'package:onepub/src/device/device_key.dart';
import 'package:pointycastle/export.dart';

Future<void> main(List<String> arguments) async {
  final directory =
      await Directory.systemTemp.createTemp('onepub-native-test-');
  DeviceKey? key;
  final result = <String, Object>{'platform': Platform.operatingSystem};
  try {
    key = await DeviceKey.create(directory);
    final reopened = await DeviceKey.open(directory);
    if (jsonEncode(reopened.publicJwk) != jsonEncode(key.publicJwk)) {
      throw StateError('Reopened hardware key changed its public key.');
    }
    for (final message in [
      <int>[],
      utf8.encode('OnePub native device key test')
    ]) {
      final bytes = await reopened.sign(message);
      if (!verify(reopened.publicJwk, message, bytes) ||
          verify(reopened.publicJwk, [...message, 0], bytes)) {
        throw StateError(
            'Native ES256 signature failed independent verification.');
      }
    }
    await key.delete();
    key = null;
    var deleted = false;
    try {
      await DeviceKey.open(directory);
    } on DeviceKeyException {
      deleted = true;
    }
    if (!deleted) {
      throw StateError('Deleted key could still be opened.');
    }
    result['status'] = 'passed';
    result['checks'] = [
      'create',
      'reopen',
      'sign-empty',
      'sign-message',
      'verify-independent-es256',
      'reject-modified-message',
      'delete'
    ];
    print(green('Native device-key create/reopen/sign/verify/delete passed.'));
  } on Object catch (error) {
    result['status'] = 'failed';
    result['error'] = error.toString();
    stderr.writeln(red('Native device-key test failed: $error'));
    exitCode = 1;
  } finally {
    await key?.delete();
    await directory.delete(recursive: true);
    final encoded = jsonEncode(result);
    print(encoded);
    if (arguments.length == 1) {
      await File(arguments.single).writeAsString(encoded, flush: true);
    }
  }
}

bool verify(Map<String, dynamic> jwk, List<int> message, List<int> bytes) {
  if (bytes.length != 64) {
    return false;
  }
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
  return verifier.verifySignature(Uint8List.fromList(message), signature);
}
