import 'dart:io';

import '../util/send_command.dart';

class MemberCreate {
  MemberCreate(EndpointResponse response) {
    _success = response.success;

    if (response.status == HttpStatus.forbidden) {
      forbidden = true;
    }

    if (!response.success) {
      errorMessage = response.data['message']! as String;
    }

  }

  late final bool _success;
  late final String name;
  late final String obfuscatedId;

  bool get success => _success;

  /// If success is false then you can check this field
  /// to see if it failed because the organisation wasn't found
  /// if this is false then a more serious error occured
  bool forbidden = false;

  /// if [success] is false this will contain the error message.
  late final String? errorMessage;
}
