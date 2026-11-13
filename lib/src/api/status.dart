import 'package:pub_semver/pub_semver.dart';

import '../exceptions.dart';

class Status {
  int statusCode;

  String message;

  late final Version version;
  final Set<String> capabilities;

  bool get supportsEnterpriseSso => capabilities.contains('enterprise-sso-v1');

  Status(this.statusCode, this.message, String? version,
      {Set<String> capabilities = const {}})
      : capabilities = Set.unmodifiable(capabilities) {
    if (version == null) {
      this.version = Version.parse('1.0.0');
    } else {
      try {
        this.version = Version.parse(version);
      } on FormatException {
        throw ExitException(
            exitCode: -1,
            message: 'Invalid version "$version" returned by Status command.');
      }
    }
  }
}
