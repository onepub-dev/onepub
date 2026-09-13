import 'dart:io';

import 'package:dcli_core/dcli_core.dart' as core;
import 'package:onepub/src/api/api.dart';
import 'package:onepub/src/api/cli_models.dart';
import 'package:onepub/src/api/member.dart';
import 'package:onepub/src/api/versions.dart';
import 'package:onepub/src/onepub_settings.dart';
import 'package:onepub/src/token_store/credential.dart';
import 'package:onepub/src/token_store/io.dart';
import 'package:onepub/src/util/one_pub_token_store.dart';
import 'package:onepub/src/util/send_command.dart';

import '../../../test_settings.dart';
import '../../../test_users.dart';
import 'publish_test_package.dart';
import 'verify_published_package.dart';

const _testUserProvisionCooldownMs = 6000;

class StagingConfig {
  final String stagingUrl;
  final String team;
  final String packagePrefix;
  final String invalidTeam;
  final String forbiddenTeam;
  final String rateRoute;
  final int rateRequests;
  final int downloadLimitRequests;
  final int downloadLimitPackageSizeMb;
  final int downloadLimitConcurrency;
  final int downloadStressRequests;
  final int downloadStressConcurrency;
  final int downloadStressPackageSizeMb;
  final String securityAlternateOrganisationId;
  final bool skipPackageCreate;
  final bool skipCleanup;
  final bool skipPublish;
  final bool skipPubGet;
  final bool skipDownloadLimit;
  final bool skipDownloadStress;
  final bool skipRateLimit;
  final bool skipRateLimitRecovery;
  final bool skipUnauthorizedTest;
  final bool skipInvalidTokenTest;
  final bool skipMetadataTest;
  final bool skipArchiveTest;
  final bool skipTeamNegative;
  final bool skipTokenInvalidation;
  final bool skipDoctor;
  final bool skipCrossOrgIsolation;

  StagingConfig({
    required this.stagingUrl,
    required this.team,
    required this.packagePrefix,
    required this.invalidTeam,
    required this.forbiddenTeam,
    required this.rateRoute,
    required this.rateRequests,
    required this.downloadLimitRequests,
    required this.downloadLimitPackageSizeMb,
    required this.downloadLimitConcurrency,
    required this.downloadStressRequests,
    required this.downloadStressConcurrency,
    required this.downloadStressPackageSizeMb,
    required this.securityAlternateOrganisationId,
    required this.skipPackageCreate,
    required this.skipCleanup,
    required this.skipPublish,
    required this.skipPubGet,
    required this.skipDownloadLimit,
    required this.skipDownloadStress,
    required this.skipRateLimit,
    required this.skipRateLimitRecovery,
    required this.skipUnauthorizedTest,
    required this.skipInvalidTokenTest,
    required this.skipMetadataTest,
    required this.skipArchiveTest,
    required this.skipTeamNegative,
    required this.skipTokenInvalidation,
    required this.skipDoctor,
    required this.skipCrossOrgIsolation,
  });

  factory StagingConfig.fromEnv({bool loadTest = false}) => StagingConfig(
        stagingUrl: TestSettings.resolveOnePubUrl(
          override: loadTest &&
                  (Platform.environment['ONEPUB_STAGING_URL'] ?? '').isEmpty
              ? TestSettings().loadTestUrl
              : null,
        ),
        team: _env('ONEPUB_TEAM', 'everyone'),
        packagePrefix: _env('ONEPUB_PACKAGE_PREFIX', 'onepub_staging_test'),
        invalidTeam: _env('ONEPUB_INVALID_TEAM', 'nonexistent-team'),
        forbiddenTeam: _env('ONEPUB_FORBIDDEN_TEAM', ''),
        rateRoute: _env('ONEPUB_RATE_ROUTE', 'organisation/details'),
        rateRequests: int.parse(_env('ONEPUB_RATE_REQUESTS', '75')),
        downloadLimitRequests:
            int.parse(_env('ONEPUB_DOWNLOAD_LIMIT_REQUESTS', '75')),
        downloadLimitPackageSizeMb:
            int.parse(_env('ONEPUB_DOWNLOAD_LIMIT_PACKAGE_SIZE_MB', '8')),
        downloadLimitConcurrency:
            int.parse(_env('ONEPUB_DOWNLOAD_LIMIT_CONCURRENCY', '20')),
        downloadStressRequests:
            int.parse(_env('ONEPUB_DOWNLOAD_STRESS_REQUESTS', '50')),
        downloadStressConcurrency:
            int.parse(_env('ONEPUB_DOWNLOAD_STRESS_CONCURRENCY', '20')),
        downloadStressPackageSizeMb:
            int.parse(_env('ONEPUB_DOWNLOAD_STRESS_PACKAGE_SIZE_MB', '0')),
        securityAlternateOrganisationId: _env('ONEPUB_SECURITY_ALT_ORG_ID', ''),
        skipPackageCreate: _flag('ONEPUB_SKIP_PACKAGE_CREATE'),
        skipCleanup: _flag('ONEPUB_SKIP_CLEANUP'),
        skipPublish: _flag('ONEPUB_SKIP_PUBLISH'),
        skipPubGet: _flag('ONEPUB_SKIP_PUB_GET'),
        skipDownloadLimit: _flag('ONEPUB_SKIP_DOWNLOAD_LIMIT'),
        skipDownloadStress: _flag('ONEPUB_SKIP_DOWNLOAD_STRESS'),
        skipRateLimit: _flag('ONEPUB_SKIP_RATE_LIMIT'),
        skipRateLimitRecovery: _flag('ONEPUB_SKIP_RATE_LIMIT_RECOVERY'),
        skipUnauthorizedTest: _flag('ONEPUB_SKIP_UNAUTHORIZED_TEST'),
        skipInvalidTokenTest: _flag('ONEPUB_SKIP_INVALID_TOKEN_TEST'),
        skipMetadataTest: _flag('ONEPUB_SKIP_METADATA_TEST'),
        skipArchiveTest: _flag('ONEPUB_SKIP_ARCHIVE_TEST'),
        skipTeamNegative: _flag('ONEPUB_SKIP_TEAM_NEGATIVE'),
        skipTokenInvalidation: _flag('ONEPUB_SKIP_TOKEN_INVALIDATION'),
        skipDoctor: _flag('ONEPUB_SKIP_DOCTOR'),
        skipCrossOrgIsolation: _flag('ONEPUB_SKIP_CROSS_ORG_ISOLATION'),
      );
}

class PublishedPackage {
  final String name;
  final String version;
  final PubVersionsBody versionsBody;

  PublishedPackage({
    required this.name,
    required this.version,
    required this.versionsBody,
  });
}

class StagingContext {
  final OnePubSettings settings;
  final String apiUrl;
  final String onepubUrl;

  StagingContext({
    required this.settings,
    required this.apiUrl,
    required this.onepubUrl,
  });
}

class ProvisionedTestOrganisation {
  final String onepubUrl;
  final String organisationName;
  final String organisationId;
  final String operatorEmail;
  final String onepubToken;
  final String plan;

  ProvisionedTestOrganisation({
    required this.onepubUrl,
    required this.organisationName,
    required this.organisationId,
    required this.operatorEmail,
    required this.onepubToken,
    required this.plan,
  });
}

var _loggedReducedCoverageWarning = false;

Future<void> ensureTestUsers(StagingConfig config,
    {String? preferredOrgId}) async {
  final isAdmin = await hasSystemAdminToken(
    config,
    preferredOrgId: preferredOrgId,
  );
  if (!isAdmin) {
    _logReducedCoverageWarning(config, preferredOrgId: preferredOrgId);
    return;
  }

  await _withTokenScope(config, preferredOrgId: preferredOrgId,
      action: (settings) async {
    final namespace = _sanitizeNamespace('''
${Uri.parse(settings.onepubUrl ?? OnePubSettings.defaultOnePubUrl).host}'''
        '-${settings.obfuscatedOrganisationId}-${TestUsers.suiteId}');
    await _respectProvisionCooldown(namespace);
    TestUsers.configureEmailNamespace(namespace);
    await TestUsers(init: true).init();
    await _recordProvisionTimestamp(namespace);
  });
}

Future<bool> hasSystemAdminToken(
  StagingConfig config, {
  String? preferredOrgId,
}) async {
  var isAdmin = false;
  await _withTokenScope(config, preferredOrgId: preferredOrgId,
      action: (_) async {
    final token = await OnePubTokenStore().load();
    final response = await retryTestSetup(
      () => API().fetchMember(token),
      (response) => response.success ? '' : response.errorMessage,
    );
    if (!response.success) {
      throw StateError(
          'Unable to check test administrator: ${response.errorMessage}');
    }
    isAdmin = response.roles.contains('SystemAdministrator');
  });
  return isAdmin;
}

void _logReducedCoverageWarning(
  StagingConfig config, {
  String? preferredOrgId,
}) {
  if (_loggedReducedCoverageWarning) {
    return;
  }
  _loggedReducedCoverageWarning = true;

  final targetUrl = TestSettings.resolveOnePubUrl(override: config.stagingUrl);
  final scopedOrg = preferredOrgId == null || preferredOrgId.isEmpty
      ? 'current organisation'
      : 'organisation $preferredOrgId';

  stderr.writeln('''
TestUsers: reduced-coverage mode. Current token for $targetUrl is not a System Administrator, so staging tests cannot provision dedicated Administrator/TeamLeader/Collaborator users for $scopedOrg.
TestUsers: admin-backed setup will be skipped and some role-separation assertions will run against the current member instead.''');
}

Future<void> _respectProvisionCooldown(String namespace) async {
  final marker = _provisionCooldownFile(namespace);
  if (!marker.existsSync()) {
    return;
  }
  final contents = marker.readAsStringSync();
  final lastProvisionMs = int.tryParse(contents.trim());
  if (lastProvisionMs == null) {
    return;
  }
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  final elapsedMs = nowMs - lastProvisionMs;
  final waitMs = _testUserProvisionCooldownMs - elapsedMs;
  if (waitMs > 0) {
    stderr.writeln(
      'TestUsers: waiting ${waitMs}ms for member API rate-limit cooldown '
      'before provisioning test users.',
    );
    await Future<void>.delayed(Duration(milliseconds: waitMs));
  }
}

Future<void> _recordProvisionTimestamp(String namespace) async {
  final marker = _provisionCooldownFile(namespace);
  await marker.parent.create(recursive: true);
  await marker.writeAsString('${DateTime.now().millisecondsSinceEpoch}');
}

File _provisionCooldownFile(String namespace) => File(
      '${Directory.systemTemp.path}/onepub_test_user_cooldown_$namespace',
    );

Future<void> withAdmin(
    StagingConfig config, Future<void> Function(StagingContext context) action,
    {String? preferredOrgId}) async {
  await withMember(config, action, preferredOrgId: preferredOrgId);
}

/// Use a suite-owned administrator so rate limits and token
/// invalidation cannot affect another suite or the bootstrap administrator.
Future<void> withSuiteAdministrator(
    StagingConfig config, Future<void> Function(StagingContext) action) async {
  if (!TestUsers.initialised) {
    await ensureTestUsers(config);
  }
  if (!TestUsers.initialised) {
    throw StateError('This test requires a dedicated test administrator.');
  }
  final member = TestUsers().administrator;
  await withScopedMemberToken(
    onepubUrl: TestSettings.resolveOnePubUrl(override: config.stagingUrl),
    member: member,
    token: member.onepubToken,
    action: action,
  );
}

Future<void> withMember(
    StagingConfig config, Future<void> Function(StagingContext context) action,
    {String? preferredOrgId}) async {
  final orgId = (preferredOrgId != null && preferredOrgId.trim().isNotEmpty)
      ? preferredOrgId.trim()
      : null;

  await _withTokenScope(config, preferredOrgId: orgId,
      action: (settings) async {
    await assertLoggedIn(settings);
    await _withContext(settings, action);
  });
}

Future<PublishedPackage> publishAndVerify(
    StagingContext context, StagingConfig config,
    {int largeNativeAssetMb = 0}) async {
  final publishResult = await publishTestPackage(
    packagePrefix: config.packagePrefix,
    apiUrl: context.apiUrl,
    team: config.team,
    skipPackageCreate: config.skipPackageCreate,
    largeNativeAssetBytes: largeNativeAssetMb * 1024 * 1024,
  );
  final versionsBody = await verifyPublishedPackage(
    packageName: publishResult.packageName,
    version: publishResult.version,
    obfuscatedOrganisationId: context.settings.obfuscatedOrganisationId,
  );
  return PublishedPackage(
    name: publishResult.packageName,
    version: publishResult.version,
    versionsBody: versionsBody,
  );
}

Future<void> withScopedMemberToken({
  required String onepubUrl,
  required Member member,
  required String token,
  required Future<void> Function(StagingContext context) action,
}) async {
  await withScopedOrganisationToken(
    onepubUrl: onepubUrl,
    operatorEmail: member.email,
    organisationName: member.organisationName,
    organisationId: member.obfuscatedOrganisationId,
    token: token,
    action: action,
  );
}

Future<void> withScopedOrganisationToken({
  required String onepubUrl,
  required String operatorEmail,
  required String organisationName,
  required String organisationId,
  required String token,
  required Future<void> Function(StagingContext context) action,
}) async {
  final tempDir = await Directory.systemTemp.createTemp('onepub_member_');
  try {
    await OnePubSettings.withPathTo(tempDir.path, () async {
      final settings = OnePubSettings.use()
        ..operatorEmail = operatorEmail
        ..organisationName = organisationName
        ..obfuscatedOrganisationId = organisationId
        ..onepubUrl =
            assertSafeOnePubTestUrl(onepubUrl, source: 'withScopedMemberToken');
      await settings.save();

      await OnePubTokenStore.withPathTo('${tempDir.path}/config/dart',
          () async {
        await OnePubTokenStore().addToken(
          onepubApiUrl: settings.onepubApiUrlAsString,
          onepubToken: token,
        );
        await core.withEnvironmentAsync(
          () => _withContext(settings, action),
          environment: {
            OnePubSettings.onepubPathEnvKey: tempDir.path,
            pubTestsConfigDirKey: '${tempDir.path}/config/dart',
            'XDG_CONFIG_HOME': '${tempDir.path}/config',
          },
        );
      });
    });
  } finally {
    await tempDir.delete(recursive: true);
  }
}

Future<ProvisionedTestOrganisation> createProvisionedTestOrganisation(
  StagingConfig config, {
  required String plan,
}) async {
  late final ProvisionedTestOrganisation provisioned;
  await _withTokenScope(config, action: (settings) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final organisationName =
        'onepub_staging_test_download_limit_${plan}_$timestamp';
    final response = await sendCommand(
      command:
          'test/organisation/create/${Uri.encodeComponent(organisationName)}'
          '?plan=${Uri.encodeQueryComponent(plan)}&dedicatedOwner=true',
      commandType: CommandType.cli,
    );
    if (!response.success) {
      throw StateError(
        'Unable to create $plan test organisation: ${response.errorMessage}',
      );
    }
    final body = response.parseCli(CliTestOrganisationBody.fromJson).body;
    if (body == null) {
      throw StateError('Missing body while creating $plan test organisation.');
    }
    if (body.onepubToken.isEmpty ||
        body.obfuscatedId.isEmpty ||
        body.organisationName.isEmpty ||
        body.operatorEmail.isEmpty) {
      throw StateError(
        'Incomplete response while creating $plan test organisation.',
      );
    }
    if (body.plan != plan) {
      throw StateError(
        'Created organisation plan mismatch. Expected $plan, got ${body.plan}.',
      );
    }

    provisioned = ProvisionedTestOrganisation(
      onepubUrl: settings.onepubUrl ?? OnePubSettings.defaultOnePubUrl,
      organisationName: body.organisationName,
      organisationId: body.obfuscatedId,
      operatorEmail: body.operatorEmail,
      onepubToken: body.onepubToken,
      plan: body.plan,
    );
  });
  return provisioned;
}

Future<void> assertLoggedIn(OnePubSettings settings) async {
  final tokenStore = OnePubTokenStore();
  if (!await tokenStore.isLoggedIn(settings.onepubApiUrl)) {
    throw StateError('''
Not logged into OnePub for ${settings.onepubApiUrl}. Run: onepub login''');
  }
}

Future<List<CliTeamInfo>> listAvailableTeams() async {
  const maxAttempts = 4;
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    final response = await sendCommand(
      command: 'test/team/list',
      commandType: CommandType.cli,
    );
    if (response.success) {
      final envelope = response.parseCli(CliTeamListBody.fromJson);
      return envelope.body?.teams ?? <CliTeamInfo>[];
    }
    if (response.status == HttpStatus.tooManyRequests &&
        attempt < maxAttempts) {
      final backoffMs = 500 * attempt;
      stderr.writeln(
        'Warning: team list hit HTTP 429 on attempt $attempt of '
        '$maxAttempts; retrying in ${backoffMs}ms...',
      );
      await Future<void>.delayed(Duration(milliseconds: backoffMs));
      continue;
    }
    throw StateError(
      'Unable to list teams: HTTP ${response.status} '
      'message="${response.errorMessage}" '
      'response=$response',
    );
  }
  return <CliTeamInfo>[];
}

Future<void> waitForCliRateLimitRecovery({
  Duration timeout = const Duration(seconds: 30),
}) async {
  final started = DateTime.now();
  while (DateTime.now().difference(started) < timeout) {
    final response = await sendCommand(
      command: 'organisation/details',
      commandType: CommandType.cli,
    );
    if (response.status != HttpStatus.tooManyRequests) {
      return;
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  throw StateError(
    'CLI rate limit did not recover within ${timeout.inSeconds} seconds.',
  );
}

Future<String?> resolveForbiddenTeam(StagingConfig config) async {
  final configured = config.forbiddenTeam.trim();
  if (configured.isNotEmpty) {
    return configured;
  }

  final teams = await listAvailableTeams();
  for (final team in teams) {
    if (team.everyoneTeam) {
      continue;
    }
    if (team.name == config.team) {
      continue;
    }
    return team.name;
  }
  return null;
}

Future<bool> hasTokenForOrganisation(
  StagingConfig config, {
  required String organisationId,
}) async {
  final trimmed = organisationId.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  final onepubUrl = TestSettings.resolveOnePubUrl(override: config.stagingUrl);
  final target = Uri.parse(onepubUrl);
  final testSettings = TestSettings();
  if (target.origin == Uri.parse(testSettings.onepubUrl).origin &&
      trimmed == testSettings.organisationId &&
      testSettings.onepubToken.trim().isNotEmpty) {
    return true;
  }
  if (trimmed == (Platform.environment['ONEPUB_TEST_ORG_ID'] ?? '').trim() &&
      (Platform.environment['ONEPUB_TOKEN'] ?? '').trim().isNotEmpty) {
    return true;
  }
  final credentials = await OnePubTokenStore().credentials;
  for (final credential in credentials) {
    if (credential.url.origin == target.origin &&
        _hasResolvableToken(credential) &&
        _extractOrganisationId(credential.url) == trimmed) {
      return true;
    }
  }
  return false;
}

String _env(String key, String fallback) =>
    Platform.environment[key] ?? fallback;

bool _flag(String key) =>
    (Platform.environment[key] ?? '').toLowerCase() == 'true';

Future<void> _withTokenScope(StagingConfig config,
    {required Future<void> Function(OnePubSettings settings) action,
    String? preferredOrgId}) async {
  final tokenInfo =
      await _loadStagingToken(config, preferredOrgIdOverride: preferredOrgId);
  final tempDir = await Directory.systemTemp.createTemp('onepub_admin_');
  try {
    await OnePubSettings.withPathTo(tempDir.path, () async {
      final settings = OnePubSettings.use()
        ..onepubUrl = tokenInfo.onepubUrl
        ..obfuscatedOrganisationId = tokenInfo.organisationId;
      await settings.save();

      await OnePubTokenStore.withPathTo('${tempDir.path}/config/dart',
          () async {
        await OnePubTokenStore().addToken(
          onepubApiUrl: settings.onepubApiUrlAsString,
          onepubToken: tokenInfo.token,
        );
        await core.withEnvironmentAsync(
          () => action(settings),
          environment: {
            OnePubSettings.onepubPathEnvKey: tempDir.path,
            pubTestsConfigDirKey: '${tempDir.path}/config/dart',
            'XDG_CONFIG_HOME': '${tempDir.path}/config',
          },
        );
      });
    });
  } finally {
    await tempDir.delete(recursive: true);
  }
}

Future<void> _withContext(OnePubSettings settings,
    Future<void> Function(StagingContext) action) async {
  final onepubUrl = settings.onepubUrl ?? OnePubSettings.defaultOnePubUrl;
  final apiUrl = settings.onepubApiUrlAsString;
  stdout
    ..writeln('OnePub URL: $onepubUrl')
    ..writeln('API URL: $apiUrl');

  await action(StagingContext(
    settings: settings,
    apiUrl: apiUrl,
    onepubUrl: onepubUrl,
  ));
}

Future<_StagingTokenInfo> _loadStagingToken(StagingConfig config,
    {String? preferredOrgIdOverride}) async {
  final testSettings = TestSettings();
  final onepubUrl = TestSettings.resolveOnePubUrl(override: config.stagingUrl);
  final target = Uri.parse(onepubUrl);
  final host = target.host;
  final preferredOrgId = testSettings.organisationId;
  final explicitOrgId =
      preferredOrgIdOverride != null && preferredOrgIdOverride.trim().isNotEmpty
          ? preferredOrgIdOverride.trim()
          : '';
  final runnerToken = (Platform.environment['ONEPUB_TOKEN'] ?? '').trim();
  final runnerOrgId = (Platform.environment['ONEPUB_TEST_ORG_ID'] ?? '').trim();

  final runnerMatchesRequestedOrganisation = explicitOrgId.isEmpty ||
      (runnerOrgId.isNotEmpty && explicitOrgId == runnerOrgId);
  if (runnerToken.isNotEmpty &&
      runnerOrgId.isNotEmpty &&
      runnerMatchesRequestedOrganisation) {
    final organisationId =
        explicitOrgId.isNotEmpty ? explicitOrgId : runnerOrgId;
    return _StagingTokenInfo(
      token: runnerToken,
      organisationId: organisationId,
      onepubUrl: onepubUrl,
    );
  }

  final configuredToken = testSettings.onepubToken.trim();
  if (configuredToken.isNotEmpty &&
      (target.origin == Uri.parse(testSettings.onepubUrl).origin ||
          (testSettings.loadTestUrl.isNotEmpty &&
              target.origin == Uri.parse(testSettings.loadTestUrl).origin)) &&
      (explicitOrgId.isEmpty || explicitOrgId == preferredOrgId)) {
    late String suiteToken;
    await withTestServer(() async {
      suiteToken = await OnePubTokenStore().load();
    }, onepubUrlOverride: onepubUrl);
    return _StagingTokenInfo(
      token: suiteToken,
      organisationId: preferredOrgId,
      onepubUrl: onepubUrl,
    );
  }

  final credentials = await OnePubTokenStore().credentials;
  Credential? match;
  for (final credential in credentials) {
    if (!_hasResolvableToken(credential)) {
      continue;
    }
    final credentialOrgId = _extractOrganisationId(credential.url);
    final desiredOrgId =
        explicitOrgId.isNotEmpty ? explicitOrgId : preferredOrgId;
    if (credential.url.origin == target.origin &&
        credentialOrgId == desiredOrgId) {
      match = credential;
      break;
    }
  }
  if (match == null && explicitOrgId.isNotEmpty) {
    throw StateError('No OnePub token found for host $host '
        'and organisationId $explicitOrgId. '
        'Run: onepub login for the Team-plan organisation and retry.');
  }
  match ??= credentials.firstWhere(
    (credential) =>
        credential.url.origin == target.origin &&
        _hasResolvableToken(credential),
    orElse: () => throw StateError(
        'No OnePub token found for host $host. Run: onepub login'),
  );

  final token = await _extractToken(match);
  final organisationId = _extractOrganisationId(match.url);
  if (organisationId == null || organisationId.isEmpty) {
    throw StateError(
        'Unable to determine organisationId from token url ${match.url}.');
  }

  return _StagingTokenInfo(
    token: token,
    organisationId: organisationId,
    onepubUrl: onepubUrl,
  );
}

bool _hasResolvableToken(Credential credential) =>
    credential.token != null ||
    (credential.env != null &&
        Platform.environment.containsKey(credential.env));

Future<String> _extractToken(Credential credential) async {
  if (credential.token != null) {
    return credential.token!;
  }
  final header = await credential.getAuthorizationHeaderValue();
  const bearer = 'Bearer ';
  return header.startsWith(bearer) ? header.substring(bearer.length) : header;
}

String? _extractOrganisationId(Uri url) {
  final segments =
      url.pathSegments.where((segment) => segment.isNotEmpty).toList();
  if (segments.length >= 2 && segments[0] == 'api') {
    return segments[1];
  }
  return null;
}

String _sanitizeNamespace(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    final char = String.fromCharCode(rune).toLowerCase();
    final isAlpha = char.codeUnitAt(0) >= 97 && char.codeUnitAt(0) <= 122;
    final isDigit = char.codeUnitAt(0) >= 48 && char.codeUnitAt(0) <= 57;
    buffer.write((isAlpha || isDigit) ? char : '_');
  }
  return buffer.toString();
}

class _StagingTokenInfo {
  final String token;
  final String organisationId;
  final String onepubUrl;

  _StagingTokenInfo({
    required this.token,
    required this.organisationId,
    required this.onepubUrl,
  });
}
