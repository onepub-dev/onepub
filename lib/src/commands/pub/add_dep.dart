// Copyright (c) 2020, the Dart project authors and OnePub IP Pty Ltd
//
// Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dcli_terminal/dcli_terminal.dart';

import '../../api/api.dart';
import '../../exceptions.dart';
import '../../onepub_settings.dart';
import '../../util/one_pub_token_store.dart';

/// Handles the `add` pub command. Adds a dependency to `pubspec.yaml` and gets
/// the package. The user may pass in a git constraint, host url, or path as
/// requirements. If no such options are passed in, this command will do a
/// resolution to find the latest version of the package that is compatible with
/// the other dependencies in `pubspec.yaml`, and then enter that as the lower
/// bound in a ^x.y.z constraint.
///
/// Currently supports only adding one dependency at a time.
class AddPrivateDependencyCommand extends Command<int> {
  AddPrivateDependencyCommand();

  @override
  String get name => 'add';

  @override
  String get description => blue('''
Add a private dependencies to `pubspec.yaml`.''');

// Invoking `onepub pub add foo` will add `foo` to `pubspec.yaml`
// with a default constraint derived from latest compatible version.

// Add to dev_dependencies by prefixing with "dev:".

// Make dependency overrides by prefixing with "override:".

// Add packages with specific constraints or other sources by giving a descriptor
// after a colon.

  @override
  Future<int> run() async {
    // cache.setDefault
    await API().checkVersion();
    return add();
  }

  Future<int> add() async {
    if (!await OnePubTokenStore()
        .isLoggedIn(OnePubSettings.use().onepubApiUrl)) {
      throw ExitException(exitCode: 1, message: '''
You must be logged in to run this command.
run: onepub login
  ''');
    }

    final onePubUrl = OnePubSettings.use().onepubApiUrlAsString;

    final r = await Process.run('dart',
        ['pub', 'add', '--hosted-url', onePubUrl, ...(argResults!.rest)]);
    stdout.write(r.stdout);
    stderr.write(r.stderr);
    return r.exitCode;
  }
}
