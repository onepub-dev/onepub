import 'dart:convert';
import 'dart:io';

/// Runs before pub get, so this script must use only Dart SDK libraries.
Future<void> main() async {
  final config = Platform.environment['_PUB_TEST_CONFIG_DIR'];
  if (config == null || config.isEmpty) {
    stderr.writeln('Missing isolated Dart credential directory.');
    exitCode = 1;
    return;
  }
  try {
    final file = File('$config/pub-tokens.json');
    if (!file.existsSync()) {
      return;
    }
    final document = jsonDecode(await file.readAsString());
    if (document is! Map<String, dynamic> ||
        document['version'] != 1 ||
        document['hosted'] is! List<dynamic>) {
      throw const FormatException('Invalid credential store.');
    }
    final entries = document['hosted'] as List<dynamic>;
    var hasPubDev = false;
    for (final entry in entries) {
      if (entry is! Map<String, dynamic> || entry['url'] is! String) {
        throw const FormatException('Invalid credential entry.');
      }
      final url = Uri.parse(entry['url'] as String);
      if (url.scheme == 'https' &&
          url.host == 'pub.dev' &&
          url.port == 443 &&
          url.userInfo.isEmpty &&
          (url.path.isEmpty || url.path == '/')) {
        hasPubDev = true;
      }
    }
    if (!hasPubDev) {
      return;
    }
    final process = await Process.start(
      Platform.resolvedExecutable,
      ['pub', 'token', 'remove', 'https://pub.dev'],
      mode: ProcessStartMode.inheritStdio,
    );
    try {
      exitCode = await process.exitCode.timeout(const Duration(seconds: 30));
    } on Object {
      process.kill();
      rethrow;
    }
  } on Object {
    stderr.writeln('Unable to clear the isolated pub.dev credential.');
    exitCode = 1;
  }
}
