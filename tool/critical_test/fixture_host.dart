#! /usr/bin/env dcli

import 'dart:io';
import 'package:dcli/dcli.dart';
import '../../../onepub-deploy/bin/op-build.dart' as fixtures;

Future<void> main(List<String> args) async {
  try {
    await fixtures.serveCliTestFixture(args[0], args[1]);
  } catch (_) {
    printerr('Local Docker test server failed.');
    File('${args[1]}/failed').writeAsStringSync('Local test server failed.');
    exitCode = 1;
  }
}
