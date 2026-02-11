import 'dart:io';

import '../util/send_command.dart';
import 'cli_models.dart';

class Organisation {
  late final bool _success;

  late final String name;

  late final String obfuscatedId;

  /// If success is false then you can check this field
  /// to see if it failed because the organisation wasn't found
  /// if this is false then a more serious error occured
  var notFound = false;

  /// if [success] is false this will contain the error message.
  late final String? errorMessage;

  Organisation(EndpointResponse response) {
    _success = response.success;

    if (response.status == HttpStatus.notFound) {
      notFound = true;
    }

    if (response.success) {
      final envelope = response.parseCli(CliOrganisationBody.fromJson);
      name = envelope.body?.organisationName ?? '';
      obfuscatedId = envelope.body?.obfuscatedId ?? '';
    } else {
      errorMessage = response.errorMessage;
    }
  }

  bool get success => _success;
}
