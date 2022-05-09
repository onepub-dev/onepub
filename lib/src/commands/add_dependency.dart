import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:pubspec/pubspec.dart';

import '../exceptions.dart';
import '../onepub_paths.dart';
import '../onepub_settings.dart';

///
class AddDependencyCommand extends Command<void> {
  ///
  AddDependencyCommand();

  @override
  String get description => '''
Adds a private package as a dependency to the current Dart Project
or updates an existing dependency to pull from your OnePub private repository.
      ''';

  @override
  String get name => 'add';

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
    if (argResults!.rest.length != 2) {
      throw ExitException(exitCode: -1, message: red('''
The add dependency command takes two arguments:
onepub add <Package> <Version Constraint>
'''));
    }

    final package = argResults!.rest[0];
    final version = argResults!.rest[1];
    final organisation = OnePubSettings().obfuscatedOrganisationId;
    final apiUrl = OnePubSettings().onepubApiUrl;
    final url = '$apiUrl/$organisation';
    final versionConstraint = VersionConstraint.parse(version);

    final deps = project.pubSpec.dependencies;
    final ref = ExternalHostedReference(package, url, versionConstraint);

    final dep = Dependency(package, ref);

    final newDependencies = <String, DependencyReference>{};
    for (final entry in deps.entries) {
      newDependencies[entry.key] = entry.value.reference;
    }
    newDependencies[package] = dep.reference;

    final pubspec = project.pubSpec.pubspec.copy(dependencies: newDependencies);
    await pubspec.save(Directory(project.pathToProjectRoot));

    print('''
$package $version has been marked as a private package.

See ${OnePubSettings().onepubWebUrl}/publish
''');
  }
}
