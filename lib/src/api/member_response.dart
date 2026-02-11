import 'dart:io';

import '../util/role_enum.dart';
import '../util/send_command.dart';
import 'cli_models.dart';
import 'member.dart';

class MemberResponse {
  late final bool _success;

  final String onepubToken;

  late final String email;

  late final String firstname;

  late final String lastname;

  late final Set<String> roles;

  late final String organisationName;

  late final String obfuscatedOrganisationId;

  /// If success is false then you can check this field
  /// to see if it failed because the organisation wasn't found
  /// if this is false then a more serious error occured
  var notFound = false;

  /// if [success] is false this will contain the error message.
  late final String? _errorMessage;

  MemberResponse(EndpointResponse response, this.onepubToken) {
    _success = response.success;

    if (response.status == HttpStatus.notFound) {
      notFound = true;
    }

    if (!response.success) {
      _errorMessage = response.errorMessage;
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

  bool get success => _success;

  String get errorMessage => _errorMessage ?? '';

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
