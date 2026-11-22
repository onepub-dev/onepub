import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:onepub/src/device/device_key.dart';
import 'package:onepub/src/device/device_session.dart';
import 'package:onepub/src/onepub_settings.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_settings.dart';

void main() {
  final enabled = Platform.environment['ONEPUB_DEVICE_PUB_E2E'] == 'true';
  test('device login uses TPM key for real pub publish and private read',
      () async {
    final toolsDirectory = _requiredEnvironment('ONEPUB_TEST_TPM_TOOLS');
    final origin = TestSettings.resolveOnePubUrl(
      override: _requiredEnvironment('ONEPUB_DEVICE_E2E_URL'),
    );
    final bridge = await _LoopbackBridge.start();
    final tpmA = await _TpmInstance.start('org.onepub.DeviceE2E.A');
    final tpmB = await _TpmInstance.start('org.onepub.DeviceE2E.B');
    final temporary =
        await Directory.systemTemp.createTemp('onepub-device-pub-e2e-');
    try {
      final a = await _enroll(
        temporary: temporary,
        label: 'a',
        origin: origin,
        tcti: tpmA.tcti,
        bridge: bridge,
      );
      final b = await _enroll(
        temporary: temporary,
        label: 'b',
        origin: origin,
        tcti: tpmB.tcti,
        bridge: bridge,
      );
      final packageName =
          'onepub_test_device_e2e_${DateTime.now().microsecondsSinceEpoch}';
      final apiUrl = a.settings.onepubApiUrlAsString;
      final package = Directory(p.join(temporary.path, 'published'))
        ..createSync();
      await File(p.join(package.path, 'pubspec.yaml')).writeAsString('''
name: $packageName
version: 1.0.0
publish_to: $apiUrl
repository: https://example.test/device-e2e
description: Temporary local device-authentication E2E package.
environment:
  sdk: '>=3.5.0 <4.0.0'
''');
      await File(p.join(package.path, 'README.md'))
          .writeAsString('Local device authentication E2E fixture.\n');
      await File(p.join(package.path, 'CHANGELOG.md'))
          .writeAsString('## 1.0.0\n- Local test fixture.\n');
      await File(p.join(package.path, 'LICENSE'))
          .writeAsString('This is a temporary test fixture.\n');
      await Directory(p.join(package.path, 'lib')).create();
      await File(p.join(package.path, 'lib', '$packageName.dart'))
          .writeAsString('const deviceE2eFixture = true;\n');

      final environmentA = a.environment(tcti: tpmA.tcti);
      await _runPatchedPub(
        ['publish', '--force'],
        workingDirectory: package.path,
        environment: environmentA,
      );

      final consumer = Directory(p.join(temporary.path, 'consumer'))
        ..createSync();
      await File(p.join(consumer.path, 'pubspec.yaml')).writeAsString('''
name: device_e2e_consumer
publish_to: none
environment:
  sdk: '>=3.5.0 <4.0.0'
dependencies:
  $packageName:
    hosted:
      name: $packageName
      url: $apiUrl
    version: ^1.0.0
''');
      await _runPatchedPub(
        ['get'],
        workingDirectory: consumer.path,
        environment: environmentA,
      );
      expect(File(p.join(consumer.path, 'pubspec.lock')).existsSync(), isTrue);
      final aPackage = await _cachedPackageFile(a.pubCache, packageName);
      final sourceBytes = await File(
        p.join(package.path, 'lib', '$packageName.dart'),
      ).readAsBytes();
      expect(await aPackage.readAsBytes(), sourceBytes);

      expect(b.session.deviceId, isNot(a.session.deviceId));
      expect(
        b.pubCache,
        isNot(a.pubCache),
        reason:
            'The second-device package read must start from an empty cache.',
      );
      await expectLater(
        DeviceKey.withLinuxBackendForTesting(
          LinuxTpmBackend.forTesting(
            tcti: tpmB.tcti,
            toolsDirectory: toolsDirectory,
          ),
          () => DeviceKey.open(a.session.storage),
        ),
        throwsA(isA<DeviceKeyException>()),
      );

      // A copied registration cannot read with the second device's TPM.
      final copiedRegistration = Map<String, String>.from(
        b.environment(tcti: tpmB.tcti),
      )
        ..['ONEPUB_PATH'] = p.dirname(a.settings.pathToSettings)
        ..['XDG_CONFIG_HOME'] = p.dirname(a.configDirectory)
        ..['HOME'] = a.home;
      final copiedRead = await Process.run(
        Platform.resolvedExecutable,
        [_patchedPub, 'get'],
        workingDirectory: consumer.path,
        environment: copiedRegistration,
        includeParentEnvironment: false,
      );
      expect(copiedRead.exitCode, isNot(0));

      final consumerB = Directory(p.join(temporary.path, 'consumer-b'))
        ..createSync();
      await File(p.join(consumerB.path, 'pubspec.yaml')).writeAsString(
          await File(p.join(consumer.path, 'pubspec.yaml')).readAsString());
      await _runPatchedPub(
        ['get'],
        workingDirectory: consumerB.path,
        environment: b.environment(tcti: tpmB.tcti),
      );
      expect(File(p.join(consumerB.path, 'pubspec.lock')).existsSync(), isTrue);
      final bPackage = await _cachedPackageFile(b.pubCache, packageName);
      expect(await bPackage.readAsBytes(), sourceBytes);

      // Exercise archive creation, attestation upload, and a second hosted
      // release through the same device-authenticated Pub helper.
      const secondVersion = 'const deviceE2eFixture = "attested-v2";\n';
      final packageSpec = File(p.join(package.path, 'pubspec.yaml'));
      await packageSpec
          .writeAsString(packageSpec.readAsStringSync().replaceFirst(
                'version: 1.0.0',
                'version: 1.0.1',
              ));
      await File(p.join(package.path, 'lib', '$packageName.dart'))
          .writeAsString(secondVersion);
      await File(p.join(package.path, 'CHANGELOG.md'))
          .writeAsString('## 1.0.1\n- Attested local test fixture.\n');
      final archive = p.join(temporary.path, '$packageName-1.0.1.tar.gz');
      await _runPatchedPub(
        ['publish', '--skip-validation', '--to-archive=$archive'],
        workingDirectory: package.path,
        environment: environmentA,
      );
      final attestation = File(p.join(temporary.path, 'attestation.json'))
        ..writeAsStringSync('{"mediaType":"sigstore"}\n');
      await _runPatchedPub(
        [
          'publish',
          '--force',
          '--from-archive=$archive',
          '--with-attestation=${attestation.path}',
        ],
        workingDirectory: package.path,
        environment: environmentA,
      );
      final consumerC = Directory(p.join(temporary.path, 'consumer-c'))
        ..createSync();
      final cacheC = Directory(p.join(temporary.path, 'pub-cache-c'))
        ..createSync();
      await File(p.join(consumerC.path, 'pubspec.yaml')).writeAsString(
        await File(p.join(consumer.path, 'pubspec.yaml')).readAsString(),
      );
      await _runPatchedPub(
        ['get'],
        workingDirectory: consumerC.path,
        environment: {
          ...b.environment(tcti: tpmB.tcti),
          'PUB_CACHE': cacheC.path,
        },
      );
      expect(File(p.join(consumerC.path, 'pubspec.lock')).existsSync(), isTrue);
      expect(
        await (await _cachedPackageFile(cacheC.path, packageName))
            .readAsString(),
        secondVersion,
      );
      final parallelTimer = Stopwatch()..start();
      await Future.wait(List.generate(4, (index) async {
        final consumer = Directory(
          p.join(temporary.path, 'parallel-consumer-$index'),
        )..createSync();
        final cache = Directory(
          p.join(temporary.path, 'parallel-cache-$index'),
        )..createSync();
        await File(p.join(consumer.path, 'pubspec.yaml')).writeAsString(
          await File(p.join(consumerC.path, 'pubspec.yaml')).readAsString(),
        );
        await _runPatchedPub(
          ['get'],
          workingDirectory: consumer.path,
          environment: {
            ...b.environment(tcti: tpmB.tcti),
            'PUB_CACHE': cache.path,
          },
        );
        expect(
          File(p.join(consumer.path, 'pubspec.lock')).existsSync(),
          isTrue,
        );
        expect(
          await (await _cachedPackageFile(cache.path, packageName))
              .readAsString(),
          secondVersion,
        );
      }));
      parallelTimer.stop();
      stdout.writeln(
        'DEVICE_PUB_E2E_PARALLEL_READS=4 '
        'elapsed_ms=${parallelTimer.elapsedMilliseconds}',
      );
    } finally {
      await tpmB.close();
      await tpmA.close();
      await bridge.close();
      await temporary.delete(recursive: true);
    }
  },
      skip: enabled ? false : 'Set ONEPUB_DEVICE_PUB_E2E=true to run.',
      tags: 'integration',
      timeout: const Timeout(Duration(minutes: 20)));
}

Future<File> _cachedPackageFile(String cache, String packageName) async {
  final hostedCache = Directory(p.join(cache, 'hosted'));
  final candidates = hostedCache
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => p.basename(file.path) == '$packageName.dart')
      .toList();
  if (candidates.length != 1) {
    throw StateError(
      'Expected one installed $packageName library file in the isolated cache; '
      'found ${candidates.length}.',
    );
  }
  return candidates.single;
}

String _requiredEnvironment(String name) {
  final value = Platform.environment[name];
  if (value == null || value.isEmpty) {
    throw StateError('Set $name to run the device pub E2E test.');
  }
  return value;
}

String get _toolsDirectory => _requiredEnvironment('ONEPUB_TEST_TPM_TOOLS');
String get _patchedPub => _requiredEnvironment('ONEPUB_DEVICE_E2E_PUB_SCRIPT');

class _Enrollment {
  _Enrollment(
    this.settings,
    this.session,
    this.configDirectory,
    this.home,
    this.pubCache,
    this.origin,
  );

  final OnePubSettings settings;
  final DeviceSession session;
  final String configDirectory;
  final String home;
  final String pubCache;
  final String origin;

  Map<String, String> environment({required String tcti}) => {
        ...Platform.environment,
        'HOME': home,
        'PUB_CACHE': pubCache,
        'ONEPUB_PATH': p.dirname(settings.pathToSettings),
        'XDG_CONFIG_HOME': p.dirname(configDirectory),
        'ONEPUB_STAGING_URL': origin,
        'ONEPUB_TEST_TPM_TCTI': tcti,
        'ONEPUB_TEST_TPM_TOOLS': _toolsDirectory,
      };
}

Future<_Enrollment> _enroll({
  required Directory temporary,
  required String label,
  required String origin,
  required String tcti,
  required _LoopbackBridge bridge,
}) async {
  final root = Directory(p.join(temporary.path, label))..createSync();
  final home = Directory(p.join(root.path, 'home'))..createSync();
  final pubCache = Directory(p.join(root.path, 'pub-cache'))
    ..createSync(recursive: true);
  final settingsDirectory = Directory(p.join(root.path, 'settings'))
    ..createSync();
  final xdgConfigHome = Directory(p.join(root.path, 'config'))
    ..createSync(recursive: true);
  final configDirectory = Directory(p.join(xdgConfigHome.path, 'dart'))
    ..createSync();
  final settings = OnePubSettings(
    pathToSettings: p.join(settingsDirectory.path, 'onepub.yaml'),
  )..onepubUrl = origin;
  await settings.save();
  final environment = <String, String>{
    ...Platform.environment,
    'HOME': home.path,
    'PUB_CACHE': pubCache.path,
    'ONEPUB_PATH': settingsDirectory.path,
    'XDG_CONFIG_HOME': xdgConfigHome.path,
    'ONEPUB_STAGING_URL': origin,
    'ONEPUB_TEST_TPM_TCTI': tcti,
    'ONEPUB_TEST_TPM_TOOLS': _toolsDirectory,
  };
  final cli = p.join(Directory.current.path, 'tool', 'test_device_cli.dart');
  final process = await Process.start(
    Platform.resolvedExecutable,
    ['run', cli, 'login', 'browser'],
    workingDirectory: Directory.current.path,
    environment: environment,
    includeParentEnvironment: false,
  );
  final authToken = Completer<String>();
  final output = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
    final match = RegExp(r'clilogin/([a-f0-9-]+)').firstMatch(line);
    if (match != null && !authToken.isCompleted) {
      authToken.complete(match.group(1)!);
    }
  });
  final errors = process.stderr.drain<void>();
  try {
    await bridge.publish(await authToken.future.timeout(
      const Duration(seconds: 30),
    ));
    final code = await process.exitCode.timeout(const Duration(seconds: 30));
    if (code != 0) throw StateError('Test CLI login exited with code $code.');
  } on Object {
    process.kill(ProcessSignal.sigkill);
    await process.exitCode;
    rethrow;
  } finally {
    await output.cancel();
    await errors;
  }
  final enrolled = OnePubSettings(pathToSettings: settings.pathToSettings);
  final session = await DeviceSession.load(enrolled, enrolled.onepubApiUrl);
  if (session == null) throw StateError('CLI login did not save enrollment.');
  final credentialFile = File(p.join(configDirectory.path, 'pub-tokens.json'));
  final credentials =
      jsonDecode(await credentialFile.readAsString()) as Map<String, dynamic>;
  final hosted = credentials['hosted'] as List<dynamic>;
  final repositoryCredential = hosted
      .cast<Map<String, dynamic>>()
      .singleWhere((value) => value['url'] == enrolled.onepubApiUrlAsString);
  if (repositoryCredential['authHelper'] is! List ||
      repositoryCredential.containsKey('token')) {
    throw StateError('Device login did not persist a helper-only credential.');
  }
  return _Enrollment(
    enrolled,
    session,
    configDirectory.path,
    home.path,
    pubCache.path,
    origin,
  );
}

Future<void> _runPatchedPub(
  List<String> arguments, {
  required String workingDirectory,
  required Map<String, String> environment,
}) async {
  final process = await Process.start(
    Platform.resolvedExecutable,
    [_patchedPub, ...arguments],
    workingDirectory: workingDirectory,
    environment: environment,
    includeParentEnvironment: false,
  );
  if (arguments.first == 'publish' && !arguments.contains('--force')) {
    process.stdin.writeln('y');
  }
  await process.stdin.close();
  final output = process.stdout.transform(utf8.decoder).join();
  final errors = process.stderr.transform(utf8.decoder).join();
  final code =
      await process.exitCode.timeout(const Duration(minutes: 4), onTimeout: () {
    process.kill(ProcessSignal.sigkill);
    throw StateError('Patched pub command timed out.');
  });
  final stdout = await output;
  final stderr = await errors;
  if (code != 0) {
    final diagnostic = '$stdout\n$stderr'.replaceAll(
        RegExp(r'(token|authorization)(\s*[:=]\s*)\S+', caseSensitive: false),
        r'$1$2[redacted]');
    throw StateError(
      'Patched pub ${arguments.first} exited with code $code: $diagnostic',
    );
  }
}

/// Loopback-only handoff used by the Selenium test to complete real browser
/// sign-in. The login challenge never leaves localhost and is not logged.
class _LoopbackBridge {
  _LoopbackBridge(this._server);

  final HttpServer _server;
  final List<String> _challenges = [];

  static Future<_LoopbackBridge> start() async {
    final port = int.parse(
      _requiredEnvironment('ONEPUB_DEVICE_E2E_BRIDGE_PORT'),
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    final bridge = _LoopbackBridge(server);
    server.listen(bridge._handle);
    return bridge;
  }

  Future<void> publish(String challenge) async {
    _challenges.add(challenge);
  }

  Future<void> _handle(HttpRequest request) async {
    if (request.connectionInfo?.remoteAddress.isLoopback != true ||
        request.uri.path != '/next-login' ||
        request.method != 'GET') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    if (_challenges.isEmpty) {
      request.response.statusCode = HttpStatus.noContent;
    } else {
      request.response.headers.contentType = ContentType.json;
      request.response
          .write(jsonEncode({'challenge': _challenges.removeAt(0)}));
    }
    await request.response.close();
  }

  Future<void> close() => _server.close(force: true);
}

class _TpmInstance {
  _TpmInstance(this.name, this.tcti, this._state, this._swtpm, this._abrmd);

  final String name;
  final String tcti;
  final Directory _state;
  final Process _swtpm;
  final Process _abrmd;

  static Future<_TpmInstance> start(String name) async {
    final swtpmPath = _requiredEnvironment('ONEPUB_TEST_TPM_SWTPM');
    final abrmdPath = _requiredEnvironment('ONEPUB_TEST_TPM_ABRMD');
    final state = await Directory.systemTemp.createTemp('onepub-tpm-device-');
    final port = await _reservePortPair();
    final swtpm = await Process.start(swtpmPath, [
      'socket',
      '--tpm2',
      '--tpmstate',
      'dir=${state.path}',
      '--server',
      'type=tcp,port=$port,bindaddr=127.0.0.1',
      '--ctrl',
      'type=tcp,port=${port + 1},bindaddr=127.0.0.1',
      '--flags',
      'not-need-init,startup-clear',
    ]);
    swtpm.stdout.listen((_) {});
    swtpm.stderr.listen((_) {});
    try {
      await _waitForPort(port + 1);
      final abrmd = await Process.start(
        abrmdPath,
        [
          '--allow-root',
          '--session',
          '--dbus-name=$name',
          '--tcti=swtpm:host=127.0.0.1,port=$port',
        ],
      );
      abrmd.stdout.listen((_) {});
      abrmd.stderr.listen((_) {});
      final tcti = 'tabrmd:bus_type=session,bus_name=$name';
      var ready = false;
      for (var attempt = 0; attempt < 100; attempt++) {
        final result = await Process.run(
          p.join(_toolsDirectory, 'tpm2_getcap'),
          ['-T', tcti, 'properties-fixed'],
        );
        if (result.exitCode == 0) {
          ready = true;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (!ready) {
        abrmd.kill(ProcessSignal.sigkill);
        await abrmd.exitCode;
        throw StateError('TPM resource manager failed to become ready.');
      }
      return _TpmInstance(name, tcti, state, swtpm, abrmd);
    } on Object {
      swtpm.kill(ProcessSignal.sigkill);
      await swtpm.exitCode;
      await state.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> close() async {
    _abrmd.kill(ProcessSignal.sigkill);
    _swtpm.kill(ProcessSignal.sigkill);
    await Future.wait([_abrmd.exitCode, _swtpm.exitCode]);
    await _state.delete(recursive: true);
  }
}

Future<int> _reservePortPair() async {
  for (var attempt = 0; attempt < 20; attempt++) {
    final first = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    try {
      if (first.port == 65535) continue;
      final second =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, first.port + 1);
      await second.close();
      return first.port;
    } on SocketException {
      // Try another pair if the next port was allocated.
    } finally {
      await first.close();
    }
  }
  throw StateError('Could not reserve adjacent TPM simulator ports.');
}

Future<void> _waitForPort(int port) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    try {
      final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
      socket.destroy();
      return;
    } on SocketException {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
  throw StateError('TPM simulator socket did not become ready.');
}
