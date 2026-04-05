import 'dart:io';

import '../util/send_command.dart';
import 'cli_models.dart';

class Organisation {
  // This field is true if the API call to get the organisation was successful.
  final bool _success;

  // The name of the organisation. This will be null if the API call
  // was not successful.
  final String? name;

  // The obfuscated id of the organisation. This will be null if the
  // API call was not successful.
  final String? obfuscatedId;

  /// If success is false then you can check this field
  /// to see if it failed because the organisation wasn't found
  /// if this is false then a more serious error occured
  var notFound = false;

  /// if [success] is false this will contain the error message.
  late final String? errorMessage;

  factory Organisation(EndpointResponse response) {
    if (response.status == HttpStatus.notFound) {
      return Organisation._notFound();
    }

    if (response.success) {
      final envelope = response.parseCli(CliOrganisationBody.fromJson);
      final name = envelope.body?.organisationName ?? '';
      final obfuscatedId = envelope.body?.obfuscatedId ?? '';
      return Organisation.success(name: name, obfuscatedId: obfuscatedId);
    } else {
      return Organisation._error(response.errorMessage);
    }
  }

  Organisation.success({
    required this.name,
    required this.obfuscatedId,
  })  : _success = true,
        notFound = false,
        errorMessage = null;

  Organisation._error(this.errorMessage)
      : _success = false,
        name = null,
        obfuscatedId = null,
        notFound = false;

  Organisation._notFound()
      : notFound = true,
        _success = false,
        name = null,
        obfuscatedId = null,
        errorMessage = null;

  bool get success => _success;
}
