#!/usr/bin/env dcli

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:dcli/dcli.dart';
import 'package:onepub/src/api/cli_models.dart';
import 'package:onepub/src/onepub_settings.dart';
import 'package:onepub/src/util/one_pub_token_store.dart';
import 'package:onepub/src/util/send_command.dart';

import '../test/test_settings.dart';

const _localUrl = 'https://squarephone.biz';
const _stagingUrl = 'https://beta.onepub.dev';
const _downloadLimitOrgIdDefault = '326';
const _dartTestConfigPath = 'dart_test.yaml';
final _onepubRepoRoot = Directory.fromUri(
  Platform.script.resolve('..'),
).absolute.path;

enum TestSuite {
  onepubCommand,
  staging,
  integration,
  unit,
  manual,
  downloadRate,
  downloadBytes,
  downloadPubFlow,
  downloadStress,
  downloadPubFlowStress,
  all,
}

void main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('system',
        abbr: 's',
        help: 'Target system: local|staging|custom',
        allowed: ['local', 'staging', 'custom'])
    ..addOption('url', help: 'Custom target URL (required for --system custom)')
    ..addOption('suite', abbr: 't', help: 'Which tests to run', allowed: [
      'onepub-command',
      'staging',
      'integration',
      'unit',
      'manual',
      'download-rate',
      'download-bytes',
      'download-pub-flow',
      'download-stress',
      'download-pub-flow-stress',
      'all',
    ])
    ..addOption('name',
        help: 'Optional dart test --plain-name filter for a single test')
    ..addMultiOption('extra',
        help: 'Additional args passed to dart test (repeatable)')
    ..addFlag('yes', abbr: 'y', help: 'Skip confirmation prompt')
    ..addFlag('dry-run', help: 'Print command and exit')
    ..addFlag('help', abbr: 'h', negatable: false);

  try {
    ArgResults results;
    try {
      results = parser.parse(args);
    } on FormatException catch (e) {
      print(red(e.message));
      _printUsage(parser);
      exit(64);
    }

    if (results['help'] as bool) {
      _printUsage(parser);
      return;
    }

    final system = (results['system'] as String?) ?? _chooseSystem();
    var targetUrl = (results['url'] as String?)?.trim();
    targetUrl = _resolveUrl(system, targetUrl);

    final suite = _parseSuite((results['suite'] as String?) ?? _chooseSuite());
    final nameFilter = (results['name'] as String?)?.trim();
    final extra = List<String>.from(results['extra'] as List<dynamic>);

    final testToken = await _ensurePreconditions(
      targetUrl: targetUrl,
      suite: suite,
      nonInteractive: results['yes'] as bool,
    );

    final command = _buildDartTestCommand(
      suite: suite,
      targetUrl: targetUrl,
      nameFilter: nameFilter,
      extra: extra,
    );

    final env = <String, String>{
      ...Platform.environment,
      'ONEPUB_STAGING_URL': targetUrl,
      'ONEPUB_TEST_ORG_ID': OnePubSettings.use().obfuscatedOrganisationId,
      'ONEPUB_DOWNLOAD_LIMIT_ORG_ID':
          OnePubSettings.use().obfuscatedOrganisationId,
      'ONEPUB_TOKEN': testToken,
      ..._localSuiteEnvOverrides(targetUrl: targetUrl, suite: suite),
    };

    print('');
    print(blue('Target URL: $targetUrl'));
    print(blue('Suite: ${_suiteLabel(suite)}'));
    print(blue('Command: ${command.join(' ')}'));

    if (results['dry-run'] as bool) {
      return;
    }

    final confirmed =
        (results['yes'] as bool) || confirm('Run this command now?');
    if (!confirmed) {
      print(yellow('Cancelled.'));
      return;
    }

    final exitCode = await _runDartTestCommand(
      command: command,
      env: env,
      suite: suite,
    );
    exit(exitCode);
    // We need to provide a nice message.
    // ignore: avoid_catching_errors
  } on StateError catch (e) {
    stderr.writeln(red(e.message));
    exit(1);
  } on Exception catch (e) {
    stderr.writeln(red(e.toString()));
    exit(1);
  }
}

Future<String> _ensurePreconditions({
  required String targetUrl,
  required TestSuite suite,
  required bool nonInteractive,
}) async {
  final settings = OnePubSettings.use();
  if (settings.onepubUrl != targetUrl) {
    settings.onepubUrl = targetUrl;
    await settings.save();
    print(yellow('Updated onepubUrl to $targetUrl in settings.'));
  }
  final token = await _ensurePrimaryTokenForTests(
    targetUrl: targetUrl,
    nonInteractive: nonInteractive,
  );
  await _ensureTestEndpointsReady(
    targetUrl: targetUrl,
    suite: suite,
  );
  return token;
}

Future<String> _ensurePrimaryTokenForTests({
  required String targetUrl,
  required bool nonInteractive,
}) async {
  final settings = OnePubSettings.use();
  final envOrgId = (Platform.environment['ONEPUB_TEST_ORG_ID'] ?? '').trim();
  final settingsOrgId = settings.obfuscatedOrganisationId.trim();
  final orgHint = envOrgId.isNotEmpty
      ? envOrgId
      : settingsOrgId.isNotEmpty
          ? settingsOrgId
          : _downloadLimitOrgIdDefault;
  final hintedApiUrl = _buildScopedApiUrl(targetUrl, orgHint);
  final hintedOrganisation = await _resolveOrganisationFromScopedApiUrl(
    targetUrl: targetUrl,
    orgId: orgHint,
  );
  final orgLabel = _formatOrganisationLabel(
    organisationName: hintedOrganisation.organisationName,
    organisationId: orgHint,
  );

  final store = OnePubTokenStore();
  final settingsToken = await _resolveConfiguredTestToken(
    targetUrl: targetUrl,
    orgId: orgHint,
  );
  final storedToken = (await store.getToken(hintedApiUrl) ?? '').trim();
  final bootstrapToken =
      (Platform.environment['ONEPUB_BOOTSTRAP_TEST_TOKEN'] ?? '').trim();
  var token = '';
  var lastProbeFailure = '';

  Future<bool> tryToken(String candidate) async {
    if (candidate.isEmpty) {
      return false;
    }
    final failure = await _probeTokenFailure(candidate);
    if (failure == null) {
      return true;
    }
    lastProbeFailure = failure;
    return false;
  }

  final candidates = <String>[
    bootstrapToken,
    settingsToken,
    storedToken,
  ];
  final seen = <String>{};

  for (final candidate in candidates) {
    if (candidate.isEmpty || !seen.add(candidate)) {
      continue;
    }
    if (await tryToken(candidate)) {
      token = candidate;
      await store.addToken(onepubApiUrl: hintedApiUrl, onepubToken: token);
      break;
    }
  }

  if (token.isEmpty || !await tryToken(token)) {
    if (nonInteractive) {
      final diagnostic = lastProbeFailure.isEmpty
          ? ''
          : ' Last probe failure: $lastProbeFailure';
      throw StateError(
        'No valid token found for $orgLabel ($hintedApiUrl).$diagnostic',
      );
    }
    token = ask('Enter OnePub token for organisation $orgLabel').trim();
    if (token.isEmpty) {
      throw StateError('No token entered for organisation $orgLabel.');
    }
    await store.addToken(onepubApiUrl: hintedApiUrl, onepubToken: token);
    if (!await tryToken(token)) {
      final diagnostic = lastProbeFailure.isEmpty
          ? ''
          : ' Last probe failure: $lastProbeFailure';
      throw StateError(
        'Provided token is invalid or expired for organisation '
        '$orgLabel.$diagnostic',
      );
    }
  }

  final organisation = await _resolveOrganisationFromToken(token);
  if (organisation.obfuscatedId.isEmpty) {
    throw StateError(
      'Unable to determine organisation details from token for $orgLabel.',
    );
  }
  final realOrgId = organisation.obfuscatedId;
  final realApiUrl = _buildScopedApiUrl(targetUrl, realOrgId);
  if (settings.obfuscatedOrganisationId != realOrgId) {
    settings.obfuscatedOrganisationId = realOrgId;
    await settings.save();
    print(yellow('Using organisationId $realOrgId for this test run.'));
  }
  final testSettings = TestSettings();
  if (testSettings.organisationId != realOrgId) {
    testSettings.organisationId = realOrgId;
    await testSettings.save();
  }
  await store.addToken(onepubApiUrl: realApiUrl, onepubToken: token);
  await _ensureDartPubToken(apiUrl: realApiUrl, token: token);
  return token;
}

Future<String> _resolveConfiguredTestToken({
  required String targetUrl,
  required String orgId,
}) async {
  try {
    final testSettings = TestSettings();
    final token = testSettings.onepubToken.trim();
    if (token.isEmpty) {
      return '';
    }
    final organisation = await _resolveOrganisationFromToken(token);
    if (organisation.obfuscatedId == orgId) {
      return token;
    }
    return await _exportTestMemberToken(
      targetUrl: targetUrl,
      orgId: orgId,
      memberEmail: testSettings.member,
      systemToken: token,
    );
  } catch (_) {
    return '';
  }
}

Future<String> _exportTestMemberToken({
  required String targetUrl,
  required String orgId,
  required String memberEmail,
  required String systemToken,
}) async {
  final tempDir = await Directory.systemTemp.createTemp('onepub_test_token_');
  try {
    return await OnePubSettings.withPathTo(tempDir.path, () async {
      final settings = OnePubSettings.use()
        ..onepubUrl = targetUrl
        ..obfuscatedOrganisationId = orgId;
      await settings.save();

      final response = await sendCommand(
        command: 'test/member/exportToken/$orgId/'
            '${Uri.encodeComponent(memberEmail)}',
        commandType: CommandType.cli,
        authorised: false,
        headers: {'authorization': systemToken},
      );
      if (!response.success) {
        throw StateError(response.errorMessage);
      }
      final envelope = response.parseCli(CliExportTokenBody.fromJson);
      final token = envelope.body?.onepubToken ?? '';
      if (token.isEmpty) {
        throw StateError('test/member/exportToken returned no token.');
      }
      return token;
    });
  } finally {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  }
}

Future<String?> _probeTokenFailure(String token) async {
  try {
    final response = await sendCommand(
      command: 'organisation/details',
      commandType: CommandType.cli,
      authorised: false,
      headers: {'authorization': token},
    );
    if (response.success) {
      return null;
    }
    final message = response.errorMessage.trim();
    final condensed = message.replaceAll(RegExp(r'\s+'), ' ');
    final snippet = condensed.length > 160
        ? '${condensed.substring(0, 160)}...'
        : condensed;
    return 'HTTP ${response.status}'
        '${snippet.isEmpty ? '' : ': $snippet'}';
  } catch (e) {
    return e.toString();
  }
}

String _buildScopedApiUrl(String targetUrl, String orgId) {
  final trimmed = targetUrl.endsWith('/')
      ? targetUrl.substring(0, targetUrl.length - 1)
      : targetUrl;
  return '$trimmed/api/$orgId/';
}

Future<CliOrganisationBody> _resolveOrganisationFromToken(String token) async {
  final response = await sendCommand(
    command: 'organisation/details',
    commandType: CommandType.cli,
    authorised: false,
    headers: {'authorization': token},
  );
  if (!response.success) {
    return CliOrganisationBody(organisationName: '', obfuscatedId: '');
  }
  final envelope = response.parseCli(CliOrganisationBody.fromJson);
  return envelope.body ??
      CliOrganisationBody(organisationName: '', obfuscatedId: '');
}

Future<CliOrganisationBody> _resolveOrganisationFromScopedApiUrl({
  required String targetUrl,
  required String orgId,
}) async {
  final tempDir = await Directory.systemTemp.createTemp('onepub_org_lookup_');
  try {
    return await OnePubSettings.withPathTo(tempDir.path, () async {
      final settings = OnePubSettings.use()
        ..onepubUrl = targetUrl
        ..obfuscatedOrganisationId = orgId;
      await settings.save();

      final response = await sendCommand(
        command: 'organisation/details/$orgId',
        commandType: CommandType.cli,
        authorised: false,
      );
      if (!response.success) {
        return CliOrganisationBody(organisationName: '', obfuscatedId: orgId);
      }
      final envelope = response.parseCli(CliOrganisationBody.fromJson);
      return envelope.body ??
          CliOrganisationBody(organisationName: '', obfuscatedId: orgId);
    });
  } catch (_) {
    return CliOrganisationBody(organisationName: '', obfuscatedId: orgId);
  } finally {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  }
}

String _formatOrganisationLabel({
  required String organisationName,
  required String organisationId,
}) {
  final trimmedName = organisationName.trim();
  if (trimmedName.isEmpty) {
    return 'orgId $organisationId';
  }
  return '$trimmedName (orgId $organisationId)';
}

Future<void> _ensureDartPubToken({
  required String apiUrl,
  required String token,
}) async {
  final process = await Process.start(
    'dart',
    ['pub', 'token', 'add', apiUrl],
    runInShell: true,
  );
  process.stdin.writeln(token);
  await process.stdin.close();
  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    throw StateError(
      'Failed to import token into dart pub token store for $apiUrl '
      '(exit code $exitCode).',
    );
  }
}

Future<void> _ensureTestEndpointsReady({
  required String targetUrl,
  required TestSuite suite,
}) async {
  if (!_suiteRequiresTestEndpoints(suite)) {
    return;
  }

  final response = await sendCommand(
    command: 'test/whoami',
    commandType: CommandType.cli,
  );

  if (response.status == HttpStatus.ok) {
    return;
  }

  final message = response.errorMessage;
  if (response.status == HttpStatus.forbidden &&
      message.contains('Test endpoints are disabled')) {
    throw StateError('''
The staging ($targetUrl) system does not have test endpoints enabled.
Server response: HTTP ${response.status} - $message
Edit /opt/onepub/config/settings.yaml, add TEST_ENDPOINTS_ENABLED: true
and restart the server.
If this is already set, check MODE is not production; production mode also disables test endpoints.
''');
  }

  throw StateError(
    'Unable to verify test endpoints via /test/whoami '
    '(HTTP ${response.status}): '
    '${message.isEmpty ? 'no error message returned' : message}',
  );
}

bool _suiteRequiresTestEndpoints(TestSuite suite) {
  switch (suite) {
    case TestSuite.unit:
    case TestSuite.manual:
      return false;
    case TestSuite.onepubCommand:
    case TestSuite.staging:
    case TestSuite.integration:
    case TestSuite.downloadRate:
    case TestSuite.downloadBytes:
    case TestSuite.downloadPubFlow:
    case TestSuite.downloadStress:
    case TestSuite.downloadPubFlowStress:
    case TestSuite.all:
      return true;
  }
}

String _chooseSystem() => menu('Select target system',
    options: ['local', 'staging', 'custom'], defaultOption: 'local');

String _chooseSuite() => menu('Select test suite',
    options: [
      'onepub-command',
      'staging',
      'integration',
      'unit',
      'manual',
      'download-rate',
      'download-bytes',
      'download-pub-flow',
      'download-stress',
      'download-pub-flow-stress',
      'all',
    ],
    defaultOption: 'all');

String _resolveUrl(String system, String? customUrl) {
  switch (system) {
    case 'local':
      return _localUrl;
    case 'staging':
      return _stagingUrl;
    case 'custom':
      final url = customUrl ?? ask('Enter target URL (https://...)');
      final uri = Uri.tryParse(url);
      if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
        throw FormatException('Invalid URL: $url');
      }
      return url;
    default:
      throw FormatException('Unknown system: $system');
  }
}

TestSuite _parseSuite(String value) {
  switch (value) {
    case 'onepub-command':
      return TestSuite.onepubCommand;
    case 'staging':
      return TestSuite.staging;
    case 'integration':
      return TestSuite.integration;
    case 'unit':
      return TestSuite.unit;
    case 'manual':
      return TestSuite.manual;
    case 'download-rate':
      return TestSuite.downloadRate;
    case 'download-bytes':
      return TestSuite.downloadBytes;
    case 'download-pub-flow':
      return TestSuite.downloadPubFlow;
    case 'download-stress':
      return TestSuite.downloadStress;
    case 'download-pub-flow-stress':
      return TestSuite.downloadPubFlowStress;
    case 'all':
      return TestSuite.all;
    default:
      throw FormatException('Unknown suite: $value');
  }
}

String _suiteLabel(TestSuite suite) {
  switch (suite) {
    case TestSuite.onepubCommand:
      return 'onepub command tests';
    case TestSuite.staging:
      return 'staging tests';
    case TestSuite.integration:
      return 'integration tagged tests';
    case TestSuite.unit:
      return 'unit tagged tests';
    case TestSuite.manual:
      return 'manual tagged tests';
    case TestSuite.downloadRate:
      return 'download rate-limit test';
    case TestSuite.downloadBytes:
      return 'download byte-limit test';
    case TestSuite.downloadPubFlow:
      return 'download pub API-flow limit test';
    case TestSuite.downloadStress:
      return 'download archive stress test';
    case TestSuite.downloadPubFlowStress:
      return 'download pub API-flow stress test';
    case TestSuite.all:
      return 'all tests (except manual unless explicitly included)';
  }
}

List<String> _buildDartTestCommand({
  required TestSuite suite,
  required String targetUrl,
  String? nameFilter,
  List<String> extra = const [],
}) {
  final args = <String>['test', '-r', 'compact'];
  final excludeTags = _excludeTagsForSuite(suite);

  if (excludeTags.isNotEmpty) {
    args
      ..add('--exclude-tags')
      ..add(excludeTags);
  }

  switch (suite) {
    case TestSuite.onepubCommand:
      args.add('test/src/onepub_command');
    case TestSuite.staging:
      args
        ..add('-t')
        ..add('staging');
    case TestSuite.integration:
      args
        ..add('-t')
        ..add('integration');
    case TestSuite.unit:
      args
        ..add('-t')
        ..add('unit');
    case TestSuite.manual:
      args
        ..add('--run-skipped')
        ..add('-t')
        ..add('manual');
    case TestSuite.downloadRate:
      args.add('test/src/onepub_command/staging/rate_limit_test.dart');
    case TestSuite.downloadBytes:
      args.add(
          'test/src/onepub_command/staging/download_bytes_limit_test.dart');
    case TestSuite.downloadPubFlow:
      args.add(
          'test/src/onepub_command/staging/download_rate_limit_pub_get_api_flow_test.dart');
    case TestSuite.downloadStress:
      args.add('test/src/onepub_command/staging/download_stress_test.dart');
    case TestSuite.downloadPubFlowStress:
      args.add(
          'test/src/onepub_command/staging/download_pub_flow_stress_test.dart');
    case TestSuite.all:
      break;
  }

  if (nameFilter != null && nameFilter.isNotEmpty) {
    args
      ..add('--plain-name')
      ..add(nameFilter);
  }

  final hasConcurrencyOverride = extra.any(_isConcurrencyArg);
  if (!hasConcurrencyOverride &&
      _shouldRunSerial(suite: suite, targetUrl: targetUrl)) {
    args
      ..add('--concurrency')
      ..add('1');
  }

  args.addAll(extra);
  return ['dart', ...args];
}

String _excludeTagsForSuite(TestSuite suite) {
  switch (suite) {
    case TestSuite.onepubCommand:
      return 'manual || staging';
    case TestSuite.staging:
      return 'manual';
    case TestSuite.integration:
      return 'manual || staging';
    case TestSuite.unit:
      return 'manual || integration || staging';
    case TestSuite.manual:
      return 'integration || staging';
    case TestSuite.downloadRate:
    case TestSuite.downloadBytes:
    case TestSuite.downloadPubFlow:
    case TestSuite.downloadStress:
    case TestSuite.downloadPubFlowStress:
    case TestSuite.all:
      return 'manual';
  }
}

Future<int> _runDartTestCommand({
  required List<String> command,
  required Map<String, String> env,
  required TestSuite suite,
}) async {
  final overrideExcludeTags = _excludeTagsForSuite(suite);
  final dartTestConfig = '$_onepubRepoRoot/$_dartTestConfigPath';
  final originalConfig =
      exists(dartTestConfig) ? File(dartTestConfig).readAsStringSync() : null;

  if (originalConfig != null) {
    final updated = _rewriteExcludeTags(
      originalConfig,
      overrideExcludeTags,
    );
    dartTestConfig.write(updated);
  }

  try {
    final process = await Process.start(
      command.first,
      command.sublist(1),
      workingDirectory: _onepubRepoRoot,
      runInShell: true,
      environment: env,
    );
    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();
    final exitCode = await process.exitCode;
    final stdoutOutput = await stdoutFuture;
    final stderrOutput = await stderrFuture;

    if (exitCode == 0) {
      _printSuccessfulTestSummary(stdoutOutput, stderrOutput);
      _printDownloadStressSummary(stdoutOutput, stderrOutput);
    } else {
      if (stdoutOutput.trim().isNotEmpty) {
        stdout.write(stdoutOutput);
        if (!stdoutOutput.endsWith('\n')) {
          stdout.writeln();
        }
      }
      if (stderrOutput.trim().isNotEmpty) {
        stderr.write(stderrOutput);
        if (!stderrOutput.endsWith('\n')) {
          stderr.writeln();
        }
      }
    }

    return exitCode;
  } finally {
    if (originalConfig != null) {
      dartTestConfig.write(originalConfig);
    }
  }
}

void _printDownloadStressSummary(String stdoutOutput, String stderrOutput) {
  final output = '$stdoutOutput\n$stderrOutput';
  final match = RegExp(
    r'Download pub flow stress workers=.*?flowLatencyMaxMs=[^\r\n]*',
    dotAll: true,
  ).firstMatch(output);
  if (match != null) {
    print(match.group(0));
  }
}

void _printSuccessfulTestSummary(String stdoutOutput, String stderrOutput) {
  final output = '$stdoutOutput\n$stderrOutput';
  final summary = _parseSuccessfulTestSummary(output);
  if (summary == null) {
    print(green('All system tests passed.'));
    return;
  }

  final skipped = summary.skipped == 0 ? '' : ', ${summary.skipped} skipped';
  print(green('All system tests passed: ${summary.passed} passed$skipped.'));
}

({int passed, int skipped})? _parseSuccessfulTestSummary(String output) {
  final clean = output.replaceAll(
    RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'),
    '',
  );
  final matches = RegExp(r'\+(\d+)(?:\s+~(\d+))?:\s+All tests passed!')
      .allMatches(clean)
      .toList();
  if (matches.isEmpty) {
    return null;
  }

  final match = matches.last;
  return (
    passed: int.parse(match.group(1)!),
    skipped: int.tryParse(match.group(2) ?? '') ?? 0,
  );
}

String _rewriteExcludeTags(String yaml, String excludeTags) {
  final lines = yaml.split('\n');
  final rewritten = <String>[];
  var replaced = false;

  for (final line in lines) {
    if (line.startsWith('exclude_tags:')) {
      rewritten.add('exclude_tags: "$excludeTags"');
      replaced = true;
    } else {
      rewritten.add(line);
    }
  }

  if (!replaced) {
    rewritten.insert(0, 'exclude_tags: "$excludeTags"');
  }

  return rewritten.join('\n');
}

Map<String, String> _localSuiteEnvOverrides({
  required String targetUrl,
  required TestSuite suite,
}) {
  if (!_isLocalTarget(targetUrl)) {
    return const <String, String>{};
  }

  final overrides = <String, String>{};
  final isStressSuite = suite == TestSuite.staging ||
      suite == TestSuite.downloadStress ||
      suite == TestSuite.downloadPubFlowStress ||
      suite == TestSuite.all;

  if (isStressSuite &&
      !Platform.environment.containsKey('ONEPUB_DOWNLOAD_STRESS_CONCURRENCY')) {
    overrides['ONEPUB_DOWNLOAD_STRESS_CONCURRENCY'] = '4';
  }
  if (isStressSuite &&
      !Platform.environment.containsKey('ONEPUB_DOWNLOAD_STRESS_REQUESTS')) {
    overrides['ONEPUB_DOWNLOAD_STRESS_REQUESTS'] = '10';
  }

  return overrides;
}

bool _isConcurrencyArg(String arg) =>
    arg == '--concurrency' || arg.startsWith('--concurrency=');

bool _shouldRunSerial({required TestSuite suite, required String targetUrl}) {
  switch (suite) {
    case TestSuite.staging:
    case TestSuite.downloadRate:
    case TestSuite.downloadBytes:
    case TestSuite.downloadPubFlow:
    case TestSuite.downloadStress:
    case TestSuite.downloadPubFlowStress:
    case TestSuite.all:
      return true;
    case TestSuite.onepubCommand:
    case TestSuite.unit:
    case TestSuite.manual:
      return false;
    case TestSuite.integration:
      return _isLocalTarget(targetUrl);
  }
}

bool _isLocalTarget(String targetUrl) {
  if (targetUrl == _localUrl) {
    return true;
  }
  final host = Uri.tryParse(targetUrl)?.host.toLowerCase();
  if (host == null || host.isEmpty) {
    return false;
  }
  if (host == 'localhost' || host == '::1') {
    return true;
  }
  final octets = host.split('.').map(int.tryParse).toList();
  return octets.length == 4 &&
      octets.every((octet) => octet != null && octet >= 0 && octet <= 255) &&
      octets.first == 127;
}

void _printUsage(ArgParser parser) {
  print('Run OnePub system tests with target/system selection.');
  print('');
  print('Examples:');
  print('  dart run tool/run_system_tests.dart');
  print('  dart run tool/run_system_tests.dart --system local --suite staging');
  print(
      '  dart run tool/run_system_tests.dart --system staging --suite download-bytes');
  print(
      '  dart run tool/run_system_tests.dart --system custom --url https://my-host --suite integration');
  print('  dart run tool/run_system_tests.dart --system local --suite all');
  print('');
  print(parser.usage);
}
