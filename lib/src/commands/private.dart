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
See https://${OnePubSettings.onepubHostName}/publish
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

    final obfuscatedPublisherId = OnePubSettings().obfuscatedPublisherId;
    final currentPublisherName = OnePubSettings().publisherName;
    final url = '${OnePubSettings().onepubApiUrl}/$obfuscatedPublisherId/';

    final pubspec = project.pubSpec.pubspec;
    if (pubspec.publishTo != null) {
      if (pubspec.publishTo.toString() == url) {
        print(orange('${pubspec.name} is already a private package.'));
        return;
      }

      final publisherName = await getPublisher(obfuscatedPublisherId);
      if (publisherName == null) {
        print(orange('${pubspec.name} is already a private package '
            'for another publisher'));
      } else {
        print(orange('${pubspec.name} is already a private package of $publisherName'));
      }
      if (!confirm('Do you want to update the publisher to $currentPublisherName?')) {
        print(red('Action cancelled'));
        return;
      }
    }

    final pubspecUpdated = pubspec.copy(publishTo: Uri.parse(url));
    await pubspecUpdated.save(Directory(project.pathToProjectRoot));

    print('''
${pubspecUpdated.name} has been marked as a private package for the publisher ${OnePubSettings().publisherName}.

Run 'dart/flutter pub publish' to publish ${pubspecUpdated.name} to OnePub

See https://${OnePubSettings.onepubHostName}/publish
''');
  }

  /// get the publisher name
  Future<String?> getPublisher(String obfuscatedId) async {
    final response = await sendCommand(command: 'publisher/$obfuscatedId');
    if (!response.success) {
      if (response.status == HttpStatus.notFound) {
        return null;
      }
      throw ExitException(exitCode: 1, message: response.data['message']! as String);
    }

    return response.data['publisherName']! as String;
  }
}
