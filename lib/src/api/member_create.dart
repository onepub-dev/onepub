import 'dart:io';

import '../exceptions.dart';
import '../util/send_command.dart';
import 'cli_models.dart';

class MemberCreate {
  late final bool _success;

  late final String email;

  late final String firstname;

  late final String lastname;

  late final String role;

  late final String organisationName;

  late final String obfuscateOrganisationId;

  /// If success is false then you can check this field
  /// to see if it failed because the organisation wasn't found
  /// if this is false then a more serious error occured
  var forbidden = false;

  /// if [success] is false this will contain the error message.
  late final String? errorMessage;

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
      role = body.lastname;
      organisationName = body.organisationName;
      obfuscateOrganisationId = body.obfuscateOrganisationId;
    }
  }

  bool get success => _success;
}
