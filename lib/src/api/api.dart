import 'dart:io';

import '../util/send_command.dart';
import 'logout.dart';
import 'member_create.dart';
import 'onepub_token.dart';
import 'organisation.dart';
import 'status.dart';

class API {
  Future<Status> status() async {
    try {
      const endpoint = '/status';

      final response = await sendCommand(command: endpoint, authorised: false);

      return Status(response.status, response.data['message']! as String);
    } on IOException {
      return Status(500, 'Connection failed');
    }
  }

  Future<Logout> logout() async {
    const endpoint = '/member/logout';
    final response = await sendCommand(command: endpoint);

    return Logout(response);
  }

  /// Fetches the [OnePubToken] for the member whos email
  /// address is [memberEmail].
  /// The member must be logged in to the cli.
  Future<OnePubToken> fetchMemberToken(String memberEmail) async {
    final endpoint = 'member/token/$memberEmail';
    final response = await sendCommand(command: endpoint);

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
        command: endpoint, authorised: false, headers: headers);

    return Organisation(response);
  }

  Future<Organisation> fetchOrganisationById(String obfuscatedId) async {
    final endpoint = 'organisation/$obfuscatedId';
    final response = await sendCommand(command: endpoint);

    /// we push the id into the map so we can share a common
    /// constructor with [fetchOrganisation]
    response.data['obfuscatedId'] = obfuscatedId;
    return Organisation(response);
  }

  /// Creates a (empty) package owned by [team]
  Future<void> createPackage(String packageName, String team) async {
    final endpoint = 'package/create/$packageName/team/$team';
    await sendCommand(command: endpoint);
  }

  Future<MemberCreate> createMember(
      String userEmail, String firstname, String lastname) async {
    final endpoint =
        'member/create?email=$userEmail&firstname=$firstname&lastname=$lastname';
    final response = await sendCommand(command: endpoint);

    return MemberCreate(response);
  }
}
