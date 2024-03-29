// Copyright (c) 2020, the Dart project authors and OnePub IP Pty Ltd
//
// Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';


import 'package:dcli_terminal/dcli_terminal.dart';

import '../../api/api.dart';
import '../../exceptions.dart';
import '../../onepub_settings.dart';
import '../../pub/command/add.dart';
import '../../util/one_pub_token_store.dart';

/// Handles the `add` pub command. Adds a dependency to `pubspec.yaml` and gets
/// the package. The user may pass in a git constraint, host url, or path as
/// requirements. If no such options are passed in, this command will do a
/// resolution to find the latest version of the package that is compatible with
/// the other dependencies in `pubspec.yaml`, and then enter that as the lower
/// bound in a ^x.y.z constraint.
///
/// Currently supports only adding one dependency at a time.
class AddPrivateDependencyCommand extends AddCommand {
  AddPrivateDependencyCommand();
  @override
  String get name => 'add';
  @override
  String get description => blue('Add private dependencies to pubspec.yaml.');
  @override
  String get argumentsDescription =>
      '<package>[:<constraint>] [<package2>[:<constraint2>]...] [options]';
  @override
  String get docUrl => 'https://dart.dev/tools/pub/cmd/pub-add';

  @override
  String hostedUrl(String? argsHostedUrl) {
    final url = OnePubSettings.use().onepubApiUrlAsString;
    print(url);
    return url;
  }

  @override
  bool get isOffline => false;

  @override
  Future<void> runProtected() async {
    if (!await OnePubTokenStore().isLoggedIn(OnePubSettings.use().onepubApiUrl)) {
      throw ExitException(exitCode: 1, message: '''
You must be logged in to run this command.
run: onepub login
  ''');
    }

    // cache.setDefault
    await API().checkVersion();
    await super.runProtected();
  }
}
