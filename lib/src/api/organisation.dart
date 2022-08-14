import 'dart:io';

import '../util/send_command.dart';

class Organisation {
  Organisation(EndpointResponse response) {
    _success = response.success;

    if (response.status == HttpStatus.notFound) {
      notFound = true;
    }

    if (!response.success) {
      errorMessage = response.data['message']! as String;
    } else {
      name = response.data['organisationName'] as String? ?? '';
      obfuscatedId = response.data['obfuscatedId']! as String? ?? '';
    }
  }

  late final bool _success;
  late final String name;
  late final String obfuscatedId;

  bool get success => _success;

  /// If success is false then you can check this field
  /// to see if it failed because the organisation wasn't found
  /// if this is false then a more serious error occured
  bool notFound = false;

  /// if [success] is false this will contain the error message.
  late final String? errorMessage;
}
