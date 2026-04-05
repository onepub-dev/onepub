import 'dart:io';

import '../util/role_enum.dart';
import '../util/send_command.dart';
import 'cli_models.dart';
import 'member.dart';

/// Parsed response for a member lookup from the OnePub API.
///
/// On failure, scalar fields are set to empty values and [errorMessage]
/// describes the failure.
class MemberResponse {
  late final bool _success;

  /// OnePub token for the member that was requested.
  final String onepubToken;

  /// Member email address when the request succeeds.
  late final String email;

  /// Member first name when the request succeeds.
  late final String firstname;

  /// Member last name when the request succeeds.
  late final String lastname;

  /// Raw role names returned by the API when the request succeeds.
  late final Set<String> roles;

  /// Organisation name associated with the member.
  late final String organisationName;

  /// Obfuscated organisation identifier associated with the member.
  late final String obfuscatedOrganisationId;

  /// If success is false then you can check this field
  /// to see if it failed because the organisation wasn't found
  /// if this is false then a more serious error occured
  var notFound = false;

  /// if [success] is false this will contain the error message.
  late final String? _errorMessage;

  /// Builds a [MemberResponse] from a raw API [response].
  MemberResponse(EndpointResponse response, this.onepubToken) {
    _success = response.success;

    if (response.status == HttpStatus.notFound) {
      notFound = true;
    }

    if (!response.success) {
      _errorMessage = response.errorMessage;
      email = '';
      firstname = '';
      lastname = '';
      roles = <String>{};
      organisationName = '';
      obfuscatedOrganisationId = '';
    } else {
      final envelope = response.parseCli(CliMemberBody.fromJson);
      final body = envelope.body;
      email = body?.email ?? '';
      firstname = body?.firstname ?? '';
      lastname = body?.lastname ?? '';
      roles = body?.roles ?? <String>{};
      organisationName = body?.organisationName ?? '';
      obfuscatedOrganisationId = body?.obfuscateOrganisationId ?? '';
    }
  }

  /// True when the API request completed successfully.
  bool get success => _success;

  /// Error message returned by the API, or an empty string on success.
  String get errorMessage => _errorMessage ?? '';

  /// Converts this response into a domain [Member].
  Member toMember() {
    final enumRoles = <RoleEnum>{};

    for (final role in roles) {
      enumRoles.add(RoleEnumHelper.byName(role));
    }
    return Member(
        onepubToken: onepubToken,
        email: email,
        firstname: firstname,
        lastname: lastname,
        roles: enumRoles,
        organisationName: organisationName,
        obfuscatedOrganisationId: obfuscatedOrganisationId);
  }
}
