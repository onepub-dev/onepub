/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'package:args/command_runner.dart';
import 'package:dcli_core/dcli_core.dart';
import 'package:dcli_input/dcli_input.dart';
import 'package:dcli_terminal/dcli_terminal.dart';
import 'package:path/path.dart';
import 'package:pubspec_manager/pubspec_manager.dart';
import 'package:scope/scope.dart';
import 'package:url_builder/url_builder.dart';

import '../../api/api.dart';
import '../../api/organisation.dart';
import '../../entry_point.dart';
import '../../exceptions.dart';
import '../../onepub_settings.dart';
import '../../util/dart_project.dart';
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
See ${urlJoin(OnePubSettings.use().onepubWebUrl, 'publish')}''';

  @override
  String get name => 'private';

  @override
  Future<int> run() async {
    await private();
    return 0;
  }

  ///
  Future<void> private() async {
    if (!await OnePubTokenStore()
        .isLoggedIn(OnePubSettings.use().onepubApiUrl)) {
      throw ExitException(exitCode: 1, message: '''
You must be logged in to run this command.
run: onepub login
  ''');
    }

    final pathToProject = DartProject.findProject(getWorkingDirectory());
    if (pathToProject == null) {
      throw ExitException(
          exitCode: 1,
          message:
              'You must be in a Dart Package directory to run this command.');
    }
    // if (!exists(OnePubSettings.use.pathToSettingsDir)) {
    //   createDir(OnePubPaths.use.pathToSettingsDir, recursive: true);
    // }
    final settings = OnePubSettings.use();
    final obfuscatedOrganisationId = settings.obfuscatedOrganisationId;
    final currentOrganisationName = settings.organisationName;
    final url = settings.onepubApiUrlAsString;

    final pubspec = PubSpec.load(directory: pathToProject);
    if (pubspec.publishTo.toString() == url) {
      print(orange('${pubspec.name.value} is already a private package.'));
      return;
    }

    await API().checkVersion();
    final organisation = await getOrganisation(obfuscatedOrganisationId);
    if (organisation == null) {
      print(orange('${pubspec.name.value} is already a private package '
          'for another organisation'));
    } else {
      print(orange('${pubspec.name.value} is already a private package of '
          '${organisation.name}'));
    }
    if (!await confirm('Do you want to change the organisation to '
        '$currentOrganisationName?')) {
      print(red('Action cancelled'));
      return;
    }

    pubspec.publishTo.set(url);
    pubspec.saveTo(join(pathToProject, 'pubspec.yaml'));

    print('''
${pubspec.name.value} has been marked as a private package for the organisation ${settings.organisationName}.

Run 'dart/flutter pub publish' to publish ${pubspec.name.value} to OnePub

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
