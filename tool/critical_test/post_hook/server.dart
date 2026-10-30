#! /usr/bin/env dcli

import 'package:dcli/dcli.dart';
import '../local_server.dart';

Future<void> main() async {
  await stopLocalServer();
  print(green('Local Docker test server stopped.'));
}
