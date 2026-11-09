import 'dart:io';

class PenTestTarget {
  PenTestTarget(String value) : origin = Uri.parse(value) {
    if (!['http', 'https'].contains(origin.scheme) ||
        origin.host.isEmpty ||
        origin.userInfo.isNotEmpty ||
        (origin.path.isNotEmpty && origin.path != '/') ||
        origin.hasQuery ||
        origin.hasFragment) {
      throw ArgumentError(
          'Target must be an HTTP(S) origin without credentials, '
          'a path, query or fragment.');
    }
    if (['onepub.dev', 'www.onepub.dev'].contains(origin.host.toLowerCase())) {
      throw ArgumentError('Production OnePub is outside this pen test scope.');
    }
  }

  final Uri origin;
  String get host => origin.host;
  String get url => origin.origin;

  Uri uri(String path, [Map<String, String>? query]) =>
      origin.replace(path: path, queryParameters: query);

  Uri encodedPath(String path) {
    final result = Uri.parse('$url$path');
    if (!owns(result)) {
      throw ArgumentError('Request left the selected target.');
    }
    return result;
  }

  bool owns(Uri uri) =>
      uri.scheme == origin.scheme &&
      uri.host == origin.host &&
      uri.port == origin.port;
}

PenTestTarget? _selectedTarget;

PenTestTarget get penTestTarget =>
    _selectedTarget ??
    PenTestTarget(Platform.environment['ONEPUB_PENTEST_TARGET'] ??
        'https://beta.onepub.dev');

void selectPenTestTarget(String value) {
  _selectedTarget = PenTestTarget(value);
}
