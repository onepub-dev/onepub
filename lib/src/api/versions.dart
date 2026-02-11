import 'dart:io';

import '../util/send_command.dart';

class Versions {
  late final bool _success;

  late final String name;

  late final bool isDiscontinued;

  late final String replacedBy;

  late final JsonVersion latest;

  late final List<JsonVersion> versions;

  /// If success is false then you can check this field
  /// to see if it failed because the organisation wasn't found
  /// if this is false then a more serious error occured
  var notFound = false;

  /// if [success] is false this will contain the error message.
  late final String? errorMessage;

  Versions(EndpointResponse response) {
    _success = response.success;

    if (response.status == HttpStatus.notFound) {
      notFound = true;
    }

    if (!response.success) {
      errorMessage = response.errorMessage;
    } else {
      final envelope = response.parsePub(PubVersionsBody.fromJson);
      final body = envelope.body;
      if (body != null) {
        name = body.name;
        isDiscontinued = body.isDiscontinued;
        replacedBy = body.replacedBy;
        latest = body.latest;
        versions = body.versions;
      } else {
        name = '';
        isDiscontinued = false;
        replacedBy = '';
        latest = JsonVersion.empty();
        versions = <JsonVersion>[];
      }
    }
  }

  bool get success => _success;
}

class PubVersionsBody {
  final String name;
  final bool isDiscontinued;
  final String replacedBy;
  final JsonVersion latest;
  final List<JsonVersion> versions;

  PubVersionsBody({
    required this.name,
    required this.isDiscontinued,
    required this.replacedBy,
    required this.latest,
    required this.versions,
  });

  factory PubVersionsBody.fromJson(Map<String, dynamic> json) =>
      PubVersionsBody(
        name: json['name'] as String? ?? '',
        isDiscontinued: json['isDiscontinued'] as bool? ?? false,
        replacedBy: json['replacedBy'] as String? ?? '',
        latest: JsonVersion.fromJson(json['latest'] as Map<String, dynamic>?),
        versions: _versionsFromJson(json['versions']),
      );
}

class JsonVersion {
  late final String version;

  late final bool retracted;

  late final String archiveUrl;

  late final Map<String, dynamic> pubspec;

  JsonVersion(Map<String, dynamic>? data) {
    version = data?['version'] as String? ?? '';
    retracted = data?['rectrated'] as bool? ?? false;
    archiveUrl = data?['archive_url'] as String? ?? '';
    pubspec = _pubspecFromJson(data?['pubspec']);
  }

  JsonVersion.empty()
      : version = '',
        retracted = false,
        archiveUrl = '',
        pubspec = const <String, dynamic>{};

  factory JsonVersion.fromJson(Map<String, dynamic>? data) => JsonVersion(data);
}

List<JsonVersion> _versionsFromJson(Object? value) {
  final list = value as List? ?? const <dynamic>[];
  final versions = <JsonVersion>[];
  for (final entry in list) {
    if (entry is Map<String, dynamic>) {
      versions.add(JsonVersion.fromJson(entry));
    } else if (entry is Map<String, Object?>) {
      versions.add(JsonVersion.fromJson(Map<String, dynamic>.from(entry)));
    }
  }
  return versions;
}

Map<String, dynamic> _pubspecFromJson(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map<String, Object?>) {
    return Map<String, dynamic>.from(value);
  }
  return <String, dynamic>{};
}
