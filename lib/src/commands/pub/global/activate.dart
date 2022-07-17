/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'package:dcli/dcli.dart';
import 'package:pub_semver/pub_semver.dart';

import '../../../exceptions.dart';
import '../../../onepub_settings.dart';
import '../../../pub/command.dart';
import '../../../pub/global_packages.dart';
import '../../../pub/system_cache.dart';
import '../../../util/one_pub_token_store.dart';

/// Imports a the onepub token generated by the onepub login process
/// and then addes it
class ActivateCommand extends PubCommand {
  ///
  ActivateCommand() : super();

  @override
  String get description =>
      blue("Make a private package's executables globally available.");

  @override
  String get name => 'activate';

  GlobalPackages? _globals;
  @override
  // ignore: overridden_fields
  late final SystemCache cache = SystemCache();

  @override
  GlobalPackages get globals => _globals ??= GlobalPackages(cache);

  late Iterable<String> args = argResults.rest;

  @override
  Future<void> runProtected() async {
    OnePubSettings.load();

    if (!OnePubTokenStore().isLoggedIn) {
      throw ExitException(exitCode: 1, message: '''
You must be logged in to run this command.
run: onepub login
  ''');
    }

    final hostedUrl = OnePubSettings().onepubHostedUrl().toString();

    final package = readArg('No package to activate given.');

    // Parse the version constraint, if there is one.
    var constraint = VersionConstraint.any;
    if (args.isNotEmpty) {
      try {
        constraint = VersionConstraint.parse(readArg());
      } on FormatException catch (error) {
        usageException(error.message);
      }
    }

    return globals.activateHosted(
      package,
      constraint,
      null, // all executables
      overwriteBinStubs: true,
      url: hostedUrl,
    );

    // print('${blue('Successfully activated into $organisationName.')}');
  }

  String readArg([String error = '']) {
    if (args.isEmpty) usageException(error);
    final arg = args.first;
    args = args.skip(1);
    return arg;
  }
}
