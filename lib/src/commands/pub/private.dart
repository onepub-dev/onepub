/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';
import 'package:url_builder/url_builder.dart';

import '../../exceptions.dart';
import '../../onepub_paths.dart';
import '../../onepub_settings.dart';
import '../../util/one_pub_token_store.dart';
import '../../util/send_command.dart';

///
class PrivateCommand extends Command<int> {
  ///
  PrivateCommand();

  @override
  String get description => '''
${blue('Marks the current package as a private package.')}

Private packages are published to your OnePub private repository.
See ${urlJoin(OnePubSettings().onepubWebUrl, 'publish')}''';

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

    final project = DartProject.findProject(pwd);
    if (project == null) {
      throw ExitException(
          exitCode: 1,
          message:
              'You must be in a Dart Package directory to run this command.');
    }
    OnePubSettings.load();
    if (!exists(OnePubPaths().pathToSettingsDir)) {
      createDir(OnePubPaths().pathToSettingsDir, recursive: true);
    }

    final obfuscatedOrganisationId = OnePubSettings().obfuscatedOrganisationId;
    final currentOrganisationName = OnePubSettings().organisationName;
    final url = OnePubSettings().onepubHostedUrl().toString();

    final pubspec = project.pubSpec.pubspec;
    if (pubspec.publishTo != null) {
      if (pubspec.publishTo.toString() == url) {
        print(orange('${pubspec.name} is already a private package.'));
        return;
      }

      final organisationName = await getOrganisation(obfuscatedOrganisationId);
      if (organisationName == null) {
        print(orange('${pubspec.name} is already a private package '
            'for another organisation'));
      } else {
        print(orange('${pubspec.name} is already a private package of '
            '$organisationName'));
      }
      if (!confirm('Do you want to update the organisation to '
          '$currentOrganisationName?')) {
        print(red('Action cancelled'));
        return;
      }
    }

    final pubspecUpdated = pubspec.copy(publishTo: Uri.parse(url));
    await pubspecUpdated.save(Directory(project.pathToProjectRoot));

    print('''
${pubspecUpdated.name} has been marked as a private package for the organisation ${OnePubSettings().organisationName}.

Run 'dart/flutter pub publish' to publish ${pubspecUpdated.name} to OnePub

See ${urlJoin(OnePubSettings().onepubWebUrl, 'publish')}
''');
  }

  /// get the organisation name
  Future<String?> getOrganisation(String obfuscatedId) async {
    final response = await sendCommand(command: 'organisation/$obfuscatedId');
    if (!response.success) {
      if (response.status == HttpStatus.notFound) {
        return null;
      }
      throw ExitException(
          exitCode: 1, message: response.data['message']! as String);
    }

    return response.data['organisationName']! as String;
  }
}
