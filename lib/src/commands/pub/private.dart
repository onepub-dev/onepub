/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart' hide PubSpec;
import 'package:pubspec2/pubspec2.dart';
import 'package:scope/scope.dart';
import 'package:url_builder/url_builder.dart';

import '../../api/api.dart';
import '../../api/organisation.dart';
import '../../entry_point.dart';
import '../../exceptions.dart';
import '../../onepub_settings.dart';
import '../../util/one_pub_token_store.dart';

///
class PrivateCommand extends Command<int> {
  ///
  PrivateCommand();

  @override
  bool get takesArguments => false;

  @override
  String get description => '''
${blue('Marks the current package as a private package.')}

Private packages are published to your OnePub private repository.
See ${urlJoin(OnePubSettings.use.onepubWebUrl, 'publish')}''';

  @override
  String get name => 'private';

  @override
  Future<int> run() async {
    await private();
    return 0;
  }

  ///
  Future<void> private() async {
    if (!OnePubTokenStore().isLoggedIn) {
      throw ExitException(
          exitCode: 1, message: "You must run 'onepub login' first.");
    }

    final project = DartProject.findProject(getWorkingDirectory());
    if (project == null) {
      throw ExitException(
          exitCode: 1,
          message:
              'You must be in a Dart Package directory to run this command.');
    }
    // if (!exists(OnePubSettings.use.pathToSettingsDir)) {
    //   createDir(OnePubPaths.use.pathToSettingsDir, recursive: true);
    // }
    final settings = OnePubSettings.use;
    final obfuscatedOrganisationId = settings.obfuscatedOrganisationId;
    final currentOrganisationName = settings.organisationName;
    final url = settings.onepubHostedUrl().toString();

    final pubspec = await PubSpec.loadFile(project.pathToPubSpec);
    if (pubspec.publishTo != null) {
      if (pubspec.publishTo.toString() == url) {
        print(orange('${pubspec.name} is already a private package.'));
        return;
      }

      final organisation = await getOrganisation(obfuscatedOrganisationId);
      if (organisation == null) {
        print(orange('${pubspec.name} is already a private package '
            'for another organisation'));
      } else {
        print(orange('${pubspec.name} is already a private package of '
            '${organisation.name}'));
      }
      if (!confirm('Do you want to change the organisation to '
          '$currentOrganisationName?')) {
        print(red('Action cancelled'));
        return;
      }
    }

    final pubspecUpdated = pubspec.copy(publishTo: Uri.parse(url));
    await pubspecUpdated.save(Directory(project.pathToProjectRoot));

    print('''
${pubspecUpdated.name} has been marked as a private package for the organisation ${settings.organisationName}.

Run 'dart/flutter pub publish' to publish ${pubspecUpdated.name} to OnePub

See ${urlJoin(settings.onepubWebUrl, 'publish')}
''');
  }

  /// Working directory defaults to the pwd but a unit test
  /// can alter it.
  String getWorkingDirectory() {
    final workingDirectory = Scope.use(
      unitTestWorkingDirectoryKey,
      withDefault: () => pwd,
    );
    return workingDirectory;
  }

  /// get the organisation name
  Future<Organisation?> getOrganisation(String obfuscatedId) async {
    final organisation = await API().fetchOrganisationById(obfuscatedId);

    if (organisation.notFound) {
      return null;
    }
    if (!organisation.success) {
      throw ExitException(exitCode: 1, message: organisation.errorMessage!);
    }

    return organisation;
  }
}
