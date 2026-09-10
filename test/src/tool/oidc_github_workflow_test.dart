import 'dart:convert';
import 'dart:io';

import 'package:onepub/src/token_store/credential.dart';
import 'package:onepub/src/token_store/token_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../../test_settings.dart';

void main() {
  test('removes only the pub.dev token in an isolated Dart token store',
      () async {
    final temp = Directory.systemTemp.createTempSync('pub-token-remove-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final config = p.join(temp.path, 'config');
    final cache = p.join(temp.path, 'cache');
    final environment = {
      ...Platform.environment,
      'XDG_CONFIG_HOME': config,
      '_PUB_TEST_CONFIG_DIR': p.join(config, 'dart'),
      'PUB_CACHE': cache,
      'PUB_DEV_TOKEN': 'pub-dev-test-secret',
      'ONEPUB_TOKEN': 'onepub-test-secret',
    };
    final tokenFile = p.join(config, 'dart', 'pub-tokens.json');

    final addPubDev = await _runPubToken(
      ['add', 'https://pub.dev', '--env-var', 'PUB_DEV_TOKEN'],
      environment,
    );
    expect(addPubDev.exitCode, 0, reason: _processFailure(addPubDev));
    final localUrl = Uri.parse(assertSafeOnePubTestUrl(
      'http://127.0.0.1:12345',
      source: 'isolated pub token regression',
    ));
    await TokenStore(p.join(config, 'dart')).addCredential(
      Credential.token(
        localUrl,
        'onepub-local-secret',
      ),
    );
    final before = _readTokens(tokenFile);
    expect(before, hasLength(2));

    final remove = await _runClearCredential(environment);
    expect(remove.exitCode, 0, reason: _processFailure(remove));
    expect(remove.stdout, contains('Removed secret token'));

    final after = _readTokens(tokenFile);
    expect(after, [
      {
        'url': localUrl.toString(),
        'token': 'onepub-local-secret',
      },
    ]);
    expect(p.isWithin(temp.path, tokenFile), isTrue);

    final removeAgain = await _runClearCredential(environment);
    expect(removeAgain.exitCode, 0, reason: _processFailure(removeAgain));
    expect(removeAgain.stdout, isEmpty);
    expect(_readTokens(tokenFile), equals(after));
  });

  test('succeeds when the isolated credential store is missing', () async {
    final temp = Directory.systemTemp.createTempSync('pub-token-missing-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final config = p.join(temp.path, 'config', 'dart');
    Directory(config).createSync(recursive: true);

    final result = await _runClearCredential(_environment(temp, config));

    expect(result.exitCode, 0, reason: _processFailure(result));
    expect(result.stdout, isEmpty);
    expect(result.stderr, isEmpty);
  });

  test('rejects a corrupt store without exposing its contents', () async {
    final temp = Directory.systemTemp.createTempSync('pub-token-corrupt-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final config = p.join(temp.path, 'config', 'dart');
    Directory(config).createSync(recursive: true);
    File(p.join(config, 'pub-tokens.json')).writeAsStringSync(
      '{"version": 1, "hosted": "bad", "token": "secret-token"}',
    );

    final result = await _runClearCredential(_environment(temp, config));

    expect(result.exitCode, 1);
    expect(_processFailure(result), contains('Unable to clear'));
    expect(_processFailure(result), isNot(contains('secret-token')));
  });

  test('fails without an isolated credential directory', () async {
    final environment = {...Platform.environment}
      ..remove('_PUB_TEST_CONFIG_DIR');

    final result = await _runClearCredential(environment);

    expect(result.exitCode, 1);
    expect(_processFailure(result), contains('Missing isolated'));
  });

  test('removes the pub.dev credential after cache restoration in the workflow',
      () {
    final workflow = loadYaml(
      File(p.join(
        Directory.current.path,
        '.github',
        'workflows',
        'oidc-github-e2e.yml',
      )).readAsStringSync(),
    ) as YamlMap;
    final jobs = workflow['jobs'] as YamlMap;
    final publish = jobs['publish'] as YamlMap;
    final steps = publish['steps'] as YamlList;

    final setup = _stepIndex(steps, 'uses', 'dart-lang/setup-dart@v1');
    final restore = _stepIndex(steps, 'name', 'Restore isolated package cache');
    final remove =
        _stepIndex(steps, 'name', 'Remove pub.dev publishing credential');
    final install = _stepIndex(steps, 'name', 'Install CLI dependencies');

    expect(setup, greaterThanOrEqualTo(0));
    expect(restore, greaterThanOrEqualTo(0));
    expect(remove, greaterThanOrEqualTo(0));
    expect(install, greaterThanOrEqualTo(0));
    expect(setup, lessThan(restore));
    expect(restore, lessThan(remove));
    expect(remove, lessThan(install));
    expect((steps[restore] as YamlMap)['run'], contains('PUB_CACHE='));
    expect((steps[remove] as YamlMap)['run'],
        'dart tool/clear_pub_dev_credential.dart');
  });
}

Map<String, String> _environment(Directory temp, String config) => {
      ...Platform.environment,
      'XDG_CONFIG_HOME': p.dirname(config),
      '_PUB_TEST_CONFIG_DIR': config,
      'PUB_CACHE': p.join(temp.path, 'cache'),
      'PUB_DEV_TOKEN': 'pub-dev-test-secret',
      'ONEPUB_TOKEN': 'onepub-test-secret',
    };

Future<ProcessResult> _runClearCredential(Map<String, String> environment) =>
    Process.run(
      Platform.resolvedExecutable,
      ['tool/clear_pub_dev_credential.dart'],
      environment: environment,
      workingDirectory: Directory.current.path,
    ).timeout(const Duration(seconds: 30));

Future<ProcessResult> _runPubToken(
  List<String> arguments,
  Map<String, String> environment,
) =>
    Process.run(
      Platform.resolvedExecutable,
      ['pub', 'token', ...arguments],
      environment: environment,
      workingDirectory: Directory.current.path,
    ).timeout(const Duration(seconds: 30));

List<Map<String, dynamic>> _readTokens(String path) {
  final document =
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  return (document['hosted'] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .map(Map<String, dynamic>.from)
      .toList();
}

int _stepIndex(YamlList steps, String key, String value) => steps.indexWhere(
      (step) => step is YamlMap && step[key] == value,
    );

String _processFailure(ProcessResult result) =>
    '${result.stdout}\n${result.stderr}';
