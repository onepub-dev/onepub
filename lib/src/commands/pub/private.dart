/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'package:args/command_runner.dart';
import 'package:dcli_core/dcli_core.dart';
import 'package:dcli_input/dcli_input.dart';
import 'package:dcli_terminal/dcli_terminal.dart';
import 'package:path/path.dart' as p;
import 'package:pubspec_manager/pubspec_manager.dart';
import 'package:scope/scope.dart';

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
See ${OnePubSettings.use().guidePublishOnePubUrl}''';

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
    final currentOrganisationName = settings.organisationName;
    final url = settings.onepubApiUrlAsString;

    final pubspec = PubSpec.load(directory: pathToProject);

    await API().checkVersion();

    /// we need to deal with a number of scenarios
    /// 1. publish_to is missing
    /// 2. publish_to exists but is empty.
    /// 3. publish_to is set to none
    /// 4. publish_to is set to another org
    /// 5. publish_to is already set to this org
    var publish = await _checkForNone(
        pubspec: pubspec, currentOrganisationName: currentOrganisationName);
    publish = publish &&
        await _checkForSelf(
            pubspec: pubspec,
            currentOrganisationName: currentOrganisationName,
            newOrgUrl: url);
    publish = publish &&
        await _checkForOther(
            pubspec: pubspec,
            currentOrganisationName: currentOrganisationName,
            newOrgUrl: url);

    if (publish) {
      _publish(
          pubspec: pubspec,
          url: url,
          pathToProject: pathToProject,
          settings: settings);
    }
  }

  void _publish(
      {required PubSpec pubspec,
      required String url,
      required String pathToProject,
      required OnePubSettings settings}) {
    pubspec.publishTo.set(url);
    pubspec.saveTo(p.join(pathToProject, 'pubspec.yaml'));

    print('''
${blue('${pubspec.name.value} has been marked as a private package for the organisation ${settings.organisationName}')}.

Run 'dart/flutter pub publish' to publish ${pubspec.name.value} to OnePub

See ${settings.guidePublishOnePubUrl}
''');
  }

  Future<bool> _checkForNone(
      {required PubSpec pubspec,
      required String currentOrganisationName}) async {
    /// If it is set to none confirm that they want to publish the package.
    if (pubspec.publishTo.isNone()) {
      print(red('''
${pubspec.name.value} is currently marked as NOT for publishing.\n'''));
      if (!await confirm('Do you still wish to continue?')) {
        print(red('Action cancelled'));
        return false;
      }
      print('\n');
    }
    return true;
  }

  Future<bool> _checkForSelf(
      {required PubSpec pubspec,
      required String currentOrganisationName,
      required String newOrgUrl}) async {
    if (!pubspec.publishTo.missing && !pubspec.publishTo.isNone()) {
      // publish_to is set to a url
      if (pubspec.publishTo.value == newOrgUrl) {
        print(orange('''
${pubspec.name.value} is already a private package of $currentOrganisationName.'''));
        return false;
      }
    }
    return true;
  }

  Future<bool> _checkForOther(
      {required PubSpec pubspec,
      required String currentOrganisationName,
      required String newOrgUrl}) async {
    if (!pubspec.publishTo.missing &&
        !pubspec.publishTo.isPubDev() &&
        !pubspec.publishTo.isNone()) {
      // publish_to is set to a url
      if (pubspec.publishTo.value != newOrgUrl) {
        print(orange('${pubspec.name.value} is already a private package '
            'for another organisation!\n'));
        if (!await confirm('Do you want to change the organisation to '
            '$currentOrganisationName?')) {
          print(red('Action cancelled'));
          return false;
        }
      }
      return true;
    }
    return true;
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
