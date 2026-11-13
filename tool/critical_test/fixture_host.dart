#! /usr/bin/env dcli

import 'dart:io';
import 'package:dcli/dcli.dart';
import '../../../onepub-deploy/bin/op-build.dart' as fixtures;

Future<void> main(List<String> args) async {
  try {
    await fixtures.serveCliTestFixture(
      args[0],
      args[1],
      cliProject: File.fromUri(Platform.script).parent.parent.parent.path,
      // This hook uses the populated member settings. The shared fixture also
      // prepares OAuth authorization; this member-only hook does not use it.
      onReady: (_) async {},
    );
  } catch (_) {
    printerr('Local Docker test server failed.');
    File('${args[1]}/failed').writeAsStringSync('Local test server failed.');
    exitCode = 1;
  }
}
