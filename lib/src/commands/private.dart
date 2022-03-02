import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';

import '../onepub_paths.dart';
import '../onepub_settings.dart';

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

    final pubspec = project.pubSpec.pubspec
        .copy(publishTo: Uri.parse(OnePubSettings().onepubWebUrl));
    await pubspec.save(Directory(project.pathToProjectRoot));

    print('''
${pubspec.name} has been marked as a private package.
Run 'dart/flutter pub publish' to publish ${pubspec.name} to OnePub

See https://onepub.dev/publish
''');
  }
}
