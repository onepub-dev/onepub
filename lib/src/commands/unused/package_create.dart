/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';
import '../../exceptions.dart';

import '../../onepub_settings.dart';
import '../../util/send_command.dart';

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
    loadSettings();

    if (argResults!.rest.length != 2) {
      throw ExitException(exitCode: -1, message: red('''
The Package create command takes two arguments:
onepub package create <Package> <Team>
'''));
    }

    final package = argResults!.rest[0];
    final team = argResults!.rest[1];

    await sendCommand(command: 'package/create/$package/team/$team');
    return 0;
  }
}
