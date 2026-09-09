import 'dart:convert';
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';

import '../auth/token_source.dart';
import '../exceptions.dart';
import '../util/role_enum.dart';
import '../util/send_command.dart';
import '../version/version.g.dart';
import 'auth_response.dart';
import 'cli_models.dart';
import 'logout.dart';
import 'member_create.dart';
import 'member_response.dart';
import 'onepub_token.dart';
import 'organisation.dart';
import 'status.dart';
import 'versions.dart';

class API {
  Future<void> checkVersion() async {
    final server = await status();

    if (server.statusCode != HttpStatus.ok) {
      throw APIException(server.message);
    }

    if (server.version.major > Version.parse(packageVersion).major) {
      throw ExitException(exitCode: -1, message: '''
The server's major version "${server.version.major}" does not match your onepub version.

Please upgrade onepub by running:
dart pub global activate onepub
          ''');
    }
  }

  Future<Status> status() async {
    try {
      const endpoint = '/status';

      final response = await sendCommand(
          command: endpoint, authorised: false, commandType: CommandType.cli);

      final body = response.requireCliBody(CliStatusBody.fromJson);
      final message = body.message;
      final version = body.version;
      return Status(
        response.status,
        message,
        version,
      );
    } on IOException {
      return Status(500, 'Connection failed', null);
    }
  }

  /// See if the user has completed the oauth login
  Future<AuthResponse> awaitLogin(String authToken) async {
    final response = await sendCommand(
        command: 'member/awaitLogin/$authToken',
        commandType: CommandType.cli,
        authorised: false);

    return AuthResponse.parse(response);
  }

  Future<Logout> logout() async {
    const endpoint = '/member/logout';
    final response =
        await sendCommand(command: endpoint, commandType: CommandType.cli);

    return Logout(response);
  }

  /// Fetches the [OnePubToken] for the member whos email
  /// address is [memberEmail].
  /// Only an Administrator can export another person token.
  Future<OnePubToken> exportMemberToken(String memberEmail) async {
    final endpoint = 'member/exportToken/${Uri.encodeComponent(memberEmail)}';
    final response =
        await sendCommand(command: endpoint, commandType: CommandType.cli);

    return OnePubToken(response);
  }

  /// Test-only endpoint for obtaining a member token scoped to
  /// [obfuscatedOrganisationId]. Requires test endpoints and a System
  /// Administrator token on the server.
  Future<OnePubToken> exportTestMemberToken({
    required String obfuscatedOrganisationId,
    required String memberEmail,
  }) async {
    final endpoint = 'test/member/exportToken/$obfuscatedOrganisationId/'
        '${Uri.encodeComponent(memberEmail)}';
    final response =
        await sendCommand(command: endpoint, commandType: CommandType.cli);

    return OnePubToken(response);
  }

  /// Fetches the organisation details associated with the [onepubToken]
  Future<Organisation> fetchOrganisation(String onepubToken) async {
    // the import is an alternate (from login) form of getting
    // authorised but we have a chicken and egg problem
    // because the [sendCommand] expects the token to be
    // in the token store which it isn't
    // So we paass the auth header directly.
    final headers = <String, String>{}..addAll({'authorization': onepubToken});

    const endpoint = '/organisation/details';

    final response = await sendCommand(
        command: endpoint,
        authorised: false,
        headers: headers,
        commandType: CommandType.cli);

    return Organisation(response);
  }

  /// Fetches the member details associated with the [onepubTokenOfTargetMember]
  Future<MemberResponse> fetchMember(
    String onepubTokenOfTargetMember,
  ) async {
    final endpoint =
        'test/member/details/${Uri.encodeComponent(onepubTokenOfTargetMember)}';

    final response =
        await sendCommand(command: endpoint, commandType: CommandType.cli);

    return MemberResponse(response, onepubTokenOfTargetMember);
  }

  Future<Organisation> fetchOrganisationById(String obfuscatedId) async {
    final endpoint =
        'organisation/details/${Uri.encodeComponent(obfuscatedId)}';
    final response =
        await sendCommand(command: endpoint, commandType: CommandType.cli);

    final organisation = Organisation(response);
    return organisation;
  }

  /// Records a successful `onepub import` against CLI logs.
  Future<void> logTokenImport({
    /// OnePub token used to authorize the audit log request.
    required String onepubToken,

    /// Where the imported token was sourced from.
    required TokenSource tokenSource,

    /// True when the import appears to be running under any CI environment.
    required bool ci,

    /// Existing logged-in OnePub token that initiated this import, if any.
    String? initiatorOnepubToken,

    /// Normalized CI provider identifier, for example `github_actions`.
    String? ciProvider,

    /// Host or machine name reported by the client environment.
    String? host,

    /// Username reported by the client environment.
    String? user,

    /// Operating system identifier reported by the Dart runtime.
    String? os,

    /// Active shell reported by the client environment.
    String? shell,
  }) async {
    const endpoint = '/member/importToken';
    final payload = <String, String>{
      'tokenSource': tokenSource.name,
      'ci': '$ci',
      'ciProvider': ciProvider ?? '',
      'host': host ?? '',
      'user': user ?? '',
      'os': os ?? '',
      'shell': shell ?? '',
    };

    final headers = <String, String>{
      'content-type': 'application/json',
      'authorization': onepubToken,
    };
    if (initiatorOnepubToken != null && initiatorOnepubToken.isNotEmpty) {
      headers['x-onepub-initiator-token'] = initiatorOnepubToken;
    }

    final response = await sendCommand(
      command: endpoint,
      commandType: CommandType.cli,
      authorised: false,
      method: Method.post,
      headers: headers,
      body: jsonEncode(payload),
      timeout: const Duration(seconds: 5),
    );
    if (!response.success) {
      throw APIException(response.errorMessage);
    }
  }

  /// Creates a (empty) package owned by [team]
  Future<void> createPackage(String packageName, String team) async {
    final endpoint = 'package/create/$packageName/team/$team';
    await sendCommand(command: endpoint, commandType: CommandType.cli);
  }

  /// Creates a member which belongs to the same organisation
  /// as the current logged in user.
  /// The user must be a SystemAdministrator to make this call.
  Future<MemberCreate> createMember(
      {required String userEmail,
      required String firstname,
      required String lastname,
      required RoleEnum role}) async {
    final endpoint = 'test/member/create'
        '?email=${Uri.encodeQueryComponent(userEmail)}'
        '&firstname=${Uri.encodeQueryComponent(firstname)}'
        '&lastname=${Uri.encodeQueryComponent(lastname)}'
        '&role=${Uri.encodeQueryComponent(role.name)}';
    final response =
        await sendCommand(command: endpoint, commandType: CommandType.cli);

    return MemberCreate(response);
  }

  /// Fetches the list of published version for [packageName]
  Future<Versions> fetchVersions(
      String obfuscatedOrganisationId, String packageName) async {
    final endpoint = '$obfuscatedOrganisationId/api/packages/$packageName';
    final response =
        await sendCommand(command: endpoint, commandType: CommandType.pub);
    if (!response.success) {
      throw APIException(response.errorMessage);
    }

    return Versions(response);
  }
}
