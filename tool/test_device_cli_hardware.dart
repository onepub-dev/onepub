#! /usr/bin/env dcli

// Exercises the real installed/source/AOT onepub _pub-auth entrypoint against
// a loopback challenge, using an actual native hardware device key.
import 'dart:convert';
import 'dart:io';

import 'package:dcli/dcli.dart';
import 'package:onepub/src/device/device_key.dart';

import '../test/test_settings.dart';
import 'test_device_key_hardware.dart' show verify;

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    throw ArgumentError('Pass the installed onepub executable path.');
  }
  final temporary = await Directory.systemTemp.createTemp('onepub-native-cli-');
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  DeviceKey? key;
  try {
    final repository = assertSafeOnePubTestUrl(
        'http://127.0.0.1:${server.port}/native-test/',
        source: 'native CLI smoke test');
    final storage = Directory('${temporary.path}/key');
    key = await DeviceKey.create(storage);
    final signingKey = key;
    final settings = File('${temporary.path}/onepub.yaml');
    await settings.writeAsString('version: 1\nonepubUrl: $repository\n');
    await File('${temporary.path}/device-enrollments.json')
        .writeAsString(jsonEncode({
      repository: {
        'deviceId': 'native-smoke-test',
        'keyDirectory': storage.path
      }
    }));
    var verified = false;
    List<int>? challenge;
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      try {
        final body = jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>;
        if (request.uri.path.endsWith('/device/challenge')) {
          challenge = utf8.encode(jsonEncode({
            ...body,
            'domain': 'onepub-device-grant-v1',
            'repository-url': repository,
            'nonce': 'native-cli-test-nonce'
          }));
          request.response.write(jsonEncode({
            'challengeId': 'native-cli-test-challenge',
            'challenge': base64UrlEncode(challenge!).replaceAll('=', '')
          }));
        } else if (request.uri.path.endsWith('/device/exchange')) {
          final signature = base64Url
              .decode(base64Url.normalize(body['signature'] as String));
          verified = challenge != null &&
              verify(signingKey.publicJwk, challenge!, signature);
          if (!verified) {
            throw StateError('Invalid native signature.');
          }
          request.response.write(jsonEncode({
            'token': 'native-cli-test-grant',
            'tokenType': 'DPoP',
            'expiresAt': DateTime.now()
                .toUtc()
                .add(const Duration(minutes: 1))
                .toIso8601String()
          }));
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
      } on Object catch (error) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write(jsonEncode({'error': error.toString()}));
      } finally {
        await request.response.close();
      }
    });
    final process = await Process.start(
        arguments.single, ['_pub-auth', '--settings', settings.path],
        workingDirectory: Directory.systemTemp.path);
    final output = utf8.decoder.bind(process.stdout).join();
    final errors = utf8.decoder.bind(process.stderr).join();
    process.stdin.writeln(jsonEncode({
      'protocolVersion': 1,
      'interactive': false,
      'action': 'acquire',
      'repository-url': repository,
      'operation': 'read',
      'package': 'native_test'
    }));
    await process.stdin.close();
    final status = await process.exitCode.timeout(const Duration(seconds: 30),
        onTimeout: () {
      process.kill();
      return -1;
    });
    final text = await output;
    if (status != 0 ||
        !verified ||
        (jsonDecode(text) as Map<String, dynamic>)['token'] !=
            'native-cli-test-grant') {
      throw StateError('Installed CLI native helper failed ($status): '
          '$text ${await errors}');
    }
    print(green('Installed onepub _pub-auth native ES256 proof verified.'));
  } finally {
    await key?.delete();
    await server.close(force: true);
    await temporary.delete(recursive: true);
  }
}
