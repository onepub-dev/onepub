import 'dart:io';

import '../exceptions.dart';
import '../util/send_command.dart';

class MemberCreate {
  MemberCreate(EndpointResponse response) {
    _success = response.success;

    if (response.status == HttpStatus.forbidden) {
      forbidden = true;
    }

    if (!response.success) {
      errorMessage = response.data['message']! as String;
    } else {
      email = extractField(response, 'email');
      firstname = extractField(response, 'firstname');
      lastname = extractField(response, 'lastname');
      role = extractField(response, 'lastname');
      organisationName = extractField(response, 'organisationName');
      obfuscateOrganisationId =
          extractField(response, 'obfuscateOrganisationId');
    }
  }

  String extractField(EndpointResponse response, String field) {
    final value = response.data[field];
    if (value == null) {
      throw APIException("Missing field '$field");
    }

    if (value is! String) {
      throw APIException("Invalid type for '$field', expected a String, "
          'received a ${value.runtimeType}');
    }

    return value;
  }

  late final bool _success;

  late final String email;
  late final String firstname;
  late final String lastname;
  late final String role;
  late final String organisationName;
  late final String obfuscateOrganisationId;

  bool get success => _success;

  /// If success is false then you can check this field
  /// to see if it failed because the organisation wasn't found
  /// if this is false then a more serious error occured
  bool forbidden = false;

  /// if [success] is false this will contain the error message.
  late final String? errorMessage;
}
