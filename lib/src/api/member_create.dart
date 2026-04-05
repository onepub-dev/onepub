import 'dart:io';

import '../exceptions.dart';
import '../util/send_command.dart';
import 'cli_models.dart';

/// Parsed response for a member creation request to the OnePub API.
///
/// On failure, [errorMessage] describes the failure and [forbidden] indicates
/// whether the request was rejected due to insufficient permissions.
class MemberCreate {
  late final bool _success;

  /// Created member email address when the request succeeds.
  late final String email;

  /// Created member first name when the request succeeds.
  late final String firstname;

  /// Created member last name when the request succeeds.
  late final String lastname;

  /// First role assigned to the created member.
  late final String role;

  /// Organisation name associated with the created member.
  late final String organisationName;

  /// Obfuscated organisation identifier associated with the created member.
  late final String obfuscateOrganisationId;

  /// If success is false then you can check this field
  /// to see if it failed because the organisation wasn't found
  /// if this is false then a more serious error occured
  var forbidden = false;

  /// if [success] is false this will contain the error message.
  late final String? errorMessage;

  /// Builds a [MemberCreate] from a raw API [response].
  MemberCreate(EndpointResponse response) {
    _success = response.success;

    if (response.status == HttpStatus.forbidden) {
      forbidden = true;
    }

    if (!response.success) {
      errorMessage = response.errorMessage;
    } else {
      final envelope = response.parseCli(CliMemberBody.fromJson);
      final body = envelope.body;
      if (body == null) {
        throw APIException('Missing response body');
      }
      email = body.email;
      firstname = body.firstname;
      lastname = body.lastname;
      role = body.roles.isNotEmpty ? body.roles.first : '';
      organisationName = body.organisationName;
      obfuscateOrganisationId = body.obfuscateOrganisationId;
    }
  }

  /// True when the API request completed successfully.
  bool get success => _success;
}
