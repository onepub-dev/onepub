import 'dart:io';

import '../util/send_command.dart';

class Versions {
  Versions(EndpointResponse response) {
    _success = response.success;

    if (response.status == HttpStatus.notFound) {
      notFound = true;
    }

    if (!response.success) {
      
      errorMessage = response.data['message']! as String;
    } else {
      name = response.data['name'] as String? ?? '';
      isDiscontinued = response.data['isDiscontinued'] as bool? ?? false;
      replacedBy = response.data['replacedBy'] as String? ?? '';
      latest = JsonVersion(response.data['latest'] as Map<String, dynamic>?);
    }
  }

  late final bool _success;
  late final String name;
  late final bool isDiscontinued;
  late final String replacedBy;
  late final JsonVersion latest;
  late final List<JsonVersion> versions;

  bool get success => _success;

  /// If success is false then you can check this field
  /// to see if it failed because the organisation wasn't found
  /// if this is false then a more serious error occured
  bool notFound = false;

  /// if [success] is false this will contain the error message.
  late final String? errorMessage;
}

class JsonVersion {
  JsonVersion(Map<String, dynamic>? data) {
    if (data != null) {
      version = data['version'] as String? ?? '';
      retracted = data['rectrated'] as bool? ?? false;
      archiveUrl = data['archive_url'] as String? ?? '';
    }
  }

  late final String version;
  late final bool retracted;
  late final String archiveUrl;
}
