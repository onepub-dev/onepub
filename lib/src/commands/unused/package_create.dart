/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';
import '../../api/api.dart';
import '../../exceptions.dart';

/// onepub Package create  <Package>
class PackageCreateCommand extends Command<int> {
  ///
  PackageCreateCommand();

  @override
  String get description => 'Creates a Package';

  @override
  String get name => 'create';

  @override
  Future<int> run() async {
    if (argResults!.rest.length != 2) {
      throw ExitException(exitCode: -1, message: red('''
The Package create command takes two arguments:
onepub package create <Package> <Team>
'''));
    }

    final package = argResults!.rest[0];
    final team = argResults!.rest[1];
    await API().createPackage(package, team);
    return 0;
  }
}
