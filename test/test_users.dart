import 'dart:async';
import 'dart:io';

import 'package:dcli/dcli.dart';
import 'package:onepub/src/api/api.dart';
import 'package:onepub/src/api/member.dart';
import 'package:onepub/src/api/member_create.dart';
import 'package:onepub/src/api/member_response.dart';
import 'package:onepub/src/api/onepub_token.dart';
import 'package:onepub/src/exceptions.dart';
import 'package:onepub/src/util/one_pub_token_store.dart';
import 'package:onepub/src/util/role_enum.dart';
import 'package:uuid/uuid.dart';

import 'test_settings.dart';

class TestUsers {
  static final _self = TestUsers._internal();

  static var initialised = false;
  static String? _emailNamespace;

  // Each test file runs in its own isolate. Keep its role users distinct from
  // concurrent suites and earlier runs, even when they use the same server.
  static final suiteId = const Uuid().v4().replaceAll('-', '').substring(0, 16);
  static var _loggedReducedCoverageWarning = false;

  late final Member administrator;

  late final Member teamLeader;

  late final Member basicMember;

  factory TestUsers({bool init = false}) {
    if (!init && !initialised) {
      throw NotInitialisedException('call TestUsers.init() first');
    }

    return _self;
  }

  static void configureEmailNamespace(String? namespace) {
    if (initialised && namespace != _emailNamespace) {
      throw StateError(
          'TestUsers already initialised; cannot change email namespace.');
    }
    _emailNamespace =
        (namespace == null || namespace.isEmpty) ? null : namespace;
  }

  TestUsers._internal();

  /// creates and caches a set of users with different roles.
  Future<void> init() async {
    if (!initialised) {
      await withTestServer(() async {
        _emailNamespace ??= _defaultNamespace();
        if (!await _hasAdminPrivileges()) {
          if (_requireAdmin()) {
            throw StateError(
                'TestUsers requires a system admin login. Run: onepub login');
          }
          final member = await _currentMember();
          _logReducedCoverageWarning(member.email);
          administrator = member;
          teamLeader = member;
          basicMember = member;
          initialised = true;
          return;
        }
        administrator =
            await createAdministrator(_scopedEmail('sysadmin@testdomain.com'));
        teamLeader = await createTeamLeader(
            _scopedEmail('teamleader-on-sys@testdomain.com'));
        basicMember = await createBasicMember(
            _scopedEmail('basicmember-on-sys@testdomain.com'));
        initialised = true;
        // cicdMember = await createCICD('cicd@testdomain.com');
      });
    }
  }

  Future<Member> createAdministrator(String emailAddress) => _fetchOrCreate(
      emailAddress: emailAddress,
      firstname: 'One',
      lastname: 'Administrator',
      role: RoleEnum.Administrator);

  Future<Member> createTeamLeader(String emailAddress) => _fetchOrCreate(
      emailAddress: emailAddress,
      firstname: 'One',
      lastname: 'TeamLeader',
      role: RoleEnum.TeamLeader);

  Future<Member> createBasicMember(String emailAddress) => _fetchOrCreate(
      emailAddress: emailAddress,
      firstname: 'One',
      lastname: 'Member',
      role: RoleEnum.Collaborator);

  Future<Member> _fetchOrCreate(
      {required String emailAddress,
      required String firstname,
      required String lastname,
      required RoleEnum role}) async {
    final tokenResponse = await _exportMemberTokenWithRetry(emailAddress);
    stderr.writeln(
      'TestUsers: resolving user "$emailAddress" for role ${role.name} '
      '(export success: ${tokenResponse.success}).',
    );
    if (tokenResponse.success) {
      // member already exists.
      final memberResponse = await _fetchMemberWithRetry(tokenResponse.token!);
      if (memberResponse.success) {
        return memberResponse.toMember();
      }
      if (_isRetryableApiFailure(memberResponse.errorMessage)) {
        throw APIException(memberResponse.errorMessage);
      }
      final fallbackEmail = _uniqueEmail(emailAddress);
      final fallbackMember = await _createFreshMemberWithRetries(
        seedEmailAddress: fallbackEmail,
        firstname: firstname,
        lastname: lastname,
        role: role,
      );
      if (fallbackMember != null) {
        stderr.writeln('''
TestUsers: existing member lookup for $emailAddress returned "${memberResponse.errorMessage}". Created fresh fallback user ${fallbackMember.email}.''');
        return fallbackMember;
      }
      throw APIException(memberResponse.errorMessage);
    } else {
      // create new member
      final createResponse = await _createMemberWithRetry(
        userEmail: emailAddress,
        firstname: firstname,
        lastname: lastname,
        role: role,
      );

      if (createResponse.success) {
        final onepubToken = await _exportMemberTokenWithRetry(
          emailAddress,
          obfuscatedOrganisationId: createResponse.obfuscateOrganisationId,
        );
        if (!onepubToken.success) {
          throw APIException(
              'Unable to fetch the OnePubToken for $emailAddress ');
        }
        return Member(
            email: emailAddress,
            firstname: firstname,
            lastname: lastname,
            roles: {role},
            organisationName: createResponse.organisationName,
            obfuscatedOrganisationId: createResponse.obfuscateOrganisationId,
            onepubToken: onepubToken.token!);
      }

      final errorMessage = createResponse.errorMessage ?? '';
      if (errorMessage.toLowerCase().contains('already exists')) {
        final existingToken = await _exportMemberTokenWithRetry(emailAddress);
        if (existingToken.success) {
          final memberResponse =
              await _fetchMemberWithRetry(existingToken.token!);
          if (memberResponse.success) {
            return memberResponse.toMember();
          }
          if (_isRetryableApiFailure(memberResponse.errorMessage)) {
            throw APIException(memberResponse.errorMessage);
          }
          final fallbackEmail = _uniqueEmail(emailAddress);
          final fallbackMember = await _createFreshMemberWithRetries(
            seedEmailAddress: fallbackEmail,
            firstname: firstname,
            lastname: lastname,
            role: role,
          );
          if (fallbackMember != null) {
            stderr.writeln('''
TestUsers: member "$emailAddress" already existed but lookup returned "${memberResponse.errorMessage}". Created fresh fallback user ${fallbackMember.email}.''');
            return fallbackMember;
          }
          throw APIException(memberResponse.errorMessage);
        }
        final fallbackEmail = _uniqueEmail(emailAddress);
        if (_isRetryableApiFailure(existingToken.errorMessage)) {
          throw APIException(
            existingToken.errorMessage ?? 'Unable to export member token.',
          );
        }
        final fallbackMember = await _createFreshMemberWithRetries(
          seedEmailAddress: fallbackEmail,
          firstname: firstname,
          lastname: lastname,
          role: role,
        );
        if (fallbackMember != null) {
          return fallbackMember;
        }
        throw APIException(existingToken.errorMessage ??
            'Unable to export member token for $emailAddress.');
      }

      throw APIException(errorMessage);
    }
  }

  Future<OnePubToken> _exportMemberTokenWithRetry(
    String emailAddress, {
    String? obfuscatedOrganisationId,
    int attempts = 5,
  }) async {
    for (var attempt = 0; attempt < attempts; attempt++) {
      final response = await _exportMemberToken(
        emailAddress,
        obfuscatedOrganisationId: obfuscatedOrganisationId,
      );
      if (response.success) {
        return response;
      }
      stderr.writeln(
        'TestUsers: exportMemberToken attempt ${attempt + 1}/$attempts for '
        '"$emailAddress" failed: ${response.errorMessage}.',
      );
      if (attempt < attempts - 1) {
        await sleepAsync(
          _retryDelayMs(attempt),
          interval: Interval.milliseconds,
        );
      } else {
        return response;
      }
    }
    return _exportMemberToken(
      emailAddress,
      obfuscatedOrganisationId: obfuscatedOrganisationId,
    );
  }

  Future<OnePubToken> _exportMemberToken(
    String emailAddress, {
    String? obfuscatedOrganisationId,
  }) =>
      API().exportTestMemberToken(
        obfuscatedOrganisationId:
            obfuscatedOrganisationId ?? TestSettings().organisationId,
        memberEmail: emailAddress,
      );

  Future<MemberResponse> _fetchMemberWithRetry(
    String onepubToken, {
    int attempts = 5,
  }) async {
    late MemberResponse response;
    for (var attempt = 0; attempt < attempts; attempt++) {
      response = await API().fetchMember(onepubToken);
      if (response.success || !_isRetryableApiFailure(response.errorMessage)) {
        return response;
      }
      stderr.writeln(
        'TestUsers: fetchMember attempt ${attempt + 1}/$attempts failed with '
        '"${response.errorMessage}". Retrying...',
      );
      if (attempt < attempts - 1) {
        await sleepAsync(
          _retryDelayMs(attempt),
          interval: Interval.milliseconds,
        );
      }
    }
    return response;
  }

  Future<MemberCreate> _createMemberWithRetry({
    required String userEmail,
    required String firstname,
    required String lastname,
    required RoleEnum role,
    int attempts = 5,
  }) async {
    late MemberCreate response;
    for (var attempt = 0; attempt < attempts; attempt++) {
      response = await API().createMember(
        userEmail: userEmail,
        firstname: firstname,
        lastname: lastname,
        role: role,
      );
      if (response.success) {
        return response;
      }
      final errorMessage = response.errorMessage ?? '';
      if (!_isRetryableApiFailure(errorMessage)) {
        return response;
      }
      stderr.writeln(
        'TestUsers: createMember attempt ${attempt + 1}/$attempts for '
        '"$userEmail" failed with "$errorMessage". Retrying...',
      );
      if (attempt < attempts - 1) {
        await sleepAsync(
          _retryDelayMs(attempt),
          interval: Interval.milliseconds,
        );
      }
    }
    return response;
  }

  Future<Member?> _createFreshMember(
      {required String emailAddress,
      required String firstname,
      required String lastname,
      required RoleEnum role}) async {
    stderr.writeln(
      'TestUsers: creating fresh fallback user "$emailAddress" for '
      'role ${role.name}.',
    );
    final createResponse = await _createMemberWithRetry(
      userEmail: emailAddress,
      firstname: firstname,
      lastname: lastname,
      role: role,
    );
    if (!createResponse.success) {
      stderr.writeln(
        'TestUsers: createMember failed for "$emailAddress": '
        '${createResponse.errorMessage}.',
      );
      return null;
    }
    final onepubToken = await _exportMemberTokenWithRetry(
      emailAddress,
      obfuscatedOrganisationId: createResponse.obfuscateOrganisationId,
    );
    if (!onepubToken.success) {
      stderr.writeln(
        'TestUsers: exportMemberToken failed for "$emailAddress": '
        '${onepubToken.errorMessage}.',
      );
      return null;
    }
    return Member(
        email: emailAddress,
        firstname: firstname,
        lastname: lastname,
        roles: {role},
        organisationName: createResponse.organisationName,
        obfuscatedOrganisationId: createResponse.obfuscateOrganisationId,
        onepubToken: onepubToken.token!);
  }

  bool _isRetryableApiFailure(String? message) {
    final normalized = (message ?? '').trim().toLowerCase();
    return normalized.isEmpty ||
        normalized == 'empty response' ||
        normalized.contains('too many cli requests') ||
        normalized.contains('too many requests') ||
        normalized.contains('rate limit');
  }

  int _retryDelayMs(int attempt) => 1500 * (attempt + 1);

  Future<Member?> _createFreshMemberWithRetries({
    required String seedEmailAddress,
    required String firstname,
    required String lastname,
    required RoleEnum role,
    int attempts = 3,
  }) async {
    var candidate = seedEmailAddress;
    for (var attempt = 0; attempt < attempts; attempt++) {
      stderr.writeln(
        'TestUsers: fallback create attempt ${attempt + 1}/$attempts '
        'using "$candidate".',
      );
      final member = await _createFreshMember(
        emailAddress: candidate,
        firstname: firstname,
        lastname: lastname,
        role: role,
      );
      if (member != null) {
        return member;
      }
      candidate = _uniqueEmail(seedEmailAddress);
    }
    stderr.writeln(
      'TestUsers: exhausted fallback create attempts for "$seedEmailAddress".',
    );
    return null;
  }

  String _uniqueEmail(String emailAddress) {
    final parts = emailAddress.split('@');
    if (parts.length != 2) {
      return '${emailAddress}_${DateTime.now().millisecondsSinceEpoch}';
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${parts[0]}_$timestamp@${parts[1]}';
  }

  String _scopedEmail(String emailAddress) {
    final prefix = _emailNamespace ?? '';
    // Leave room for the role name and suite id in the email local part.
    final shortened = prefix.length > 20 ? prefix.substring(0, 20) : prefix;
    final namespace = shortened.isEmpty ? suiteId : '${shortened}_$suiteId';
    final parts = emailAddress.split('@');
    if (parts.length != 2) {
      return '${emailAddress}_$namespace';
    }
    return '${parts[0]}+$namespace@${parts[1]}';
  }

  String? _defaultNamespace() {
    final envNamespace = Platform.environment['ONEPUB_TEST_NAMESPACE'];
    if (envNamespace != null && envNamespace.isNotEmpty) {
      return _sanitizeNamespace(envNamespace);
    }
    try {
      final settings = TestSettings();
      final host = Uri.parse(settings.onepubUrl).host;
      final orgId = settings.organisationId;
      if (host.isEmpty || orgId.isEmpty) {
        return null;
      }
      return _sanitizeNamespace('$host-$orgId');
    } catch (_) {
      return null;
    }
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

  Future<bool> _hasAdminPrivileges() async {
    final member = await _currentMember();
    return member.roles.contains(RoleEnum.SystemAdministrator);
  }

  bool _requireAdmin() =>
      (Platform.environment['ONEPUB_TEST_REQUIRE_ADMIN'] ?? '').toLowerCase() ==
      'true';

  Future<Member> _currentMember() async {
    final token = await OnePubTokenStore().load();
    final response = await retryTestSetup(
      () => API().fetchMember(token),
      (response) => response.success ? '' : response.errorMessage,
    );
    if (!response.success) {
      final message = response.errorMessage.trim();
      final effective = message.isEmpty || message == 'Empty response'
          ? 'Unable to resolve current member from OnePub token. '
              'The token may be invalid/expired or scoped to a different '
              'organisation.'
          : message;
      throw APIException(effective);
    }
    return response.toMember();
  }

  void _logReducedCoverageWarning(String email) {
    if (_loggedReducedCoverageWarning) {
      return;
    }
    _loggedReducedCoverageWarning = true;
    stderr.writeln('''
TestUsers: reduced-coverage mode. Current member $email will be reused for Administrator, TeamLeader, and Collaborator test roles because the active token is not a System Administrator.
TestUsers: dedicated role-based test users will not be provisioned, so role-separation coverage is reduced for this run.''');
  }
}
