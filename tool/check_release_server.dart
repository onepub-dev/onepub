import 'dart:io';

import 'package:onepub/src/api/cli_models.dart';
import 'package:onepub/src/onepub_settings.dart';
import 'package:onepub/src/util/send_command.dart';

import '../test/test_settings.dart';

/// Read-only preflight for the production-equivalent staging smoke suite.
/// Never contacts production or reads/writes the operator's credentials.
Future<void> main(List<String> args) async {
  Directory? temp;
  try {
    if (args.length > 2) {
      throw ArgumentError(
          'Usage: dart run tool/check_release_server.dart [url] [version]');
    }
    final url = TestSettings.resolveOnePubUrl(
        override: args.isEmpty ? null : args.first);
    final expectedVersion = args.length == 2 ? args[1] : '5.17.2';
    temp = Directory.systemTemp.createTempSync('onepub-release-check-');
    await OnePubSettings.withPathTo(temp.path, () async {
      OnePubSettings.use().onepubUrl = url;
      final response = await sendCommand(
        command: '/status',
        commandType: CommandType.cli,
        authorised: false,
        timeout: const Duration(seconds: 5),
      );
      final status = response.requireCliBody(CliStatusBody.fromJson);
      if (status.version != expectedVersion) {
        throw StateError('Expected onepub-vaadin $expectedVersion at $url; '
            'received ${status.version}.');
      }
      stdout.writeln('Release test target verified: $url ($expectedVersion).');
    });
  } on Object catch (e) {
    stderr.writeln('Release preflight failed: $e');
    exitCode = 1;
  } finally {
    temp?.deleteSync(recursive: true);
  }
}
