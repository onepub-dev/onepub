import 'dart:io';

import 'package:pub_semver/pub_semver.dart';

import '../exceptions.dart';
import '../util/send_command.dart';
import '../version/version.g.dart';
import 'auth_response.dart';
import 'logout.dart';
import 'member_create.dart';
import 'onepub_token.dart';
import 'organisation.dart';
import 'status.dart';
import 'versions.dart';

class API {
  Future<void> checkVersion() async {
    final result = await status();

    if (result.version.major != Version.parse(packageVersion).major) {
      throw ExitException(exitCode: -1, message: '''
The server's major version "${result.version.major}" does not match your onepub version.

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

      return Status(response.status, response.data['message']! as String,
          response.data['version'] as String?);
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
  /// The member must be logged in to the cli.
  Future<OnePubToken> fetchMemberToken(String memberEmail) async {
    final endpoint = 'member/token/$memberEmail';
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

    const endpoint = '/organisation/token';

    final response = await sendCommand(
        command: endpoint,
        authorised: false,
        headers: headers,
        commandType: CommandType.cli);

    return Organisation(response);
  }

  Future<Organisation> fetchOrganisationById(String obfuscatedId) async {
    final endpoint = 'organisation/$obfuscatedId';
    final response =
        await sendCommand(command: endpoint, commandType: CommandType.cli);

    /// we push the id into the map so we can share a common
    /// constructor with [fetchOrganisation]
    response.data['obfuscatedId'] = obfuscatedId;
    return Organisation(response);
  }

  /// Creates a (empty) package owned by [team]
  Future<void> createPackage(String packageName, String team) async {
    final endpoint = 'package/create/$packageName/team/$team';
    await sendCommand(command: endpoint, commandType: CommandType.cli);
  }

  Future<MemberCreate> createMember(
      String userEmail, String firstname, String lastname) async {
    final endpoint =
        'member/create?email=$userEmail&firstname=$firstname&lastname=$lastname';
    final response =
        await sendCommand(command: endpoint, commandType: CommandType.cli);

    return MemberCreate(response);
  }

  /// Fetches the list of published version for [packageName]
  Future<Versions> fetchVersions(
      String obsfucatedOrganisationId, String packageName) async {
    final endpoint = '$obsfucatedOrganisationId/api/packages/$packageName';
    final response =
        await sendCommand(command: endpoint, commandType: CommandType.pub);

    return Versions(response);
  }
}
