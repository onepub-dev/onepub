import 'dart:async';
import 'dart:io';

import 'package:dcli/dcli.dart';
import 'package:onepub/src/api/api.dart';
import 'package:onepub/src/api/member.dart';
import 'package:onepub/src/api/onepub_token.dart';
import 'package:onepub/src/exceptions.dart';
import 'package:onepub/src/util/one_pub_token_store.dart';
import 'package:onepub/src/util/role_enum.dart';

import 'test_settings.dart';

class TestUsers {
  static final _self = TestUsers._internal();

  static var initialised = false;
  static String? _emailNamespace;

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
        initialised = true;
        _emailNamespace ??= _defaultNamespace();
        if (!await _hasAdminPrivileges()) {
          if (_requireAdmin()) {
            throw StateError(
                'TestUsers requires a system admin login. Run: onepub login');
          }
          final member = await _currentMember();
          stderr.writeln('''
TestUsers: using current member ${member.email} for all roles (no admin permissions).''');
          administrator = member;
          teamLeader = member;
          basicMember = member;
          return;
        }
        administrator =
            await createAdministrator(_scopedEmail('sysadmin@testdomain.com'));
        teamLeader = await createTeamLeader(
            _scopedEmail('teamleader-on-sys@testdomain.com'));
        basicMember = await createBasicMember(
            _scopedEmail('basicmember-on-sys@testdomain.com'));
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
    if (tokenResponse.success) {
      // member already exists.
      final memberResponse = await API().fetchMember(tokenResponse.token!);
      if (memberResponse.success) {
        return memberResponse.toMember();
      } else {
        throw APIException(memberResponse.errorMessage);
      }
    } else {
      // create new member
      final createResponse = await API().createMember(
        userEmail: emailAddress,
        firstname: firstname,
        lastname: lastname,
        role: role,
      );

      if (createResponse.success) {
        final onepubToken = await _exportMemberTokenWithRetry(emailAddress);
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
          final memberResponse = await API().fetchMember(existingToken.token!);
          if (memberResponse.success) {
            return memberResponse.toMember();
          }
          throw APIException(memberResponse.errorMessage);
        }
        final fallbackEmail = _uniqueEmail(emailAddress);
        final fallbackMember = await _createFreshMember(
            emailAddress: fallbackEmail,
            firstname: firstname,
            lastname: lastname,
            role: role);
        if (fallbackMember != null) {
          return fallbackMember;
        }
        throw APIException(existingToken.errorMessage ??
            'Unable to export member token for $emailAddress.');
      }

      throw APIException(errorMessage);
    }
  }

  Future<OnePubToken> _exportMemberTokenWithRetry(String emailAddress,
      {int attempts = 3}) async {
    for (var attempt = 0; attempt < attempts; attempt++) {
      final response = await API().exportMemberToken(emailAddress);
      if (response.success) {
        return response;
      }
      if (attempt < attempts - 1) {
        await sleepAsync(500 * (attempt + 1), interval: Interval.milliseconds);
      } else {
        return response;
      }
    }
    return API().exportMemberToken(emailAddress);
  }

  Future<Member?> _createFreshMember(
      {required String emailAddress,
      required String firstname,
      required String lastname,
      required RoleEnum role}) async {
    final createResponse = await API().createMember(
      userEmail: emailAddress,
      firstname: firstname,
      lastname: lastname,
      role: role,
    );
    if (!createResponse.success) {
      return null;
    }
    final onepubToken = await _exportMemberTokenWithRetry(emailAddress);
    if (!onepubToken.success) {
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

  String _uniqueEmail(String emailAddress) {
    final parts = emailAddress.split('@');
    if (parts.length != 2) {
      return '${emailAddress}_${DateTime.now().millisecondsSinceEpoch}';
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${parts[0]}_$timestamp@${parts[1]}';
  }

  String _scopedEmail(String emailAddress) {
    final namespace = _emailNamespace;
    if (namespace == null || namespace.isEmpty) {
      return emailAddress;
    }
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
    try {
      return await Member.isSystemAdministrator();
    } catch (_) {
      return false;
    }
  }

  bool _requireAdmin() =>
      (Platform.environment['ONEPUB_TEST_REQUIRE_ADMIN'] ?? '').toLowerCase() ==
      'true';

  Future<Member> _currentMember() async {
    final token = await OnePubTokenStore().load();
    final response = await API().fetchMember(token);
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
}
