import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';

import '../exceptions.dart';
import '../onepub_paths.dart';
import '../onepub_settings.dart';
import '../util/send_command.dart';

///
class PrivateCommand extends Command<void> {
  ///
  PrivateCommand();

  @override
  String get description => '''
Marks the current package as a private package.
Private packages are published to your OnePub private repository.
See https://onepub.dev/publish
      ''';

  @override
  String get name => 'private';

  @override
  Future<void> run() async {
    await private();
  }

  ///
  Future<void> private() async {
    final project = DartProject.findProject(pwd);
    if (project == null) {
      printerr('You must be in a Dart Package directory to run this command.');
      return;
    }
    OnePubSettings.load();
    if (!exists(OnePubPaths().pathToSettingsDir)) {
      createDir(OnePubPaths().pathToSettingsDir, recursive: true);
    }

    final obfuscatedOrganisationId = OnePubSettings().obfuscatedOrganisationId;
    final currentOrganisationName = OnePubSettings().organisationName;
    final url = '${OnePubSettings().onepubApiUrl}/$obfuscatedOrganisationId/';

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

See ${OnePubSettings().onepubWebUrl}/publish
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
