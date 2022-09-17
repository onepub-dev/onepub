/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'package:dcli/dcli.dart' hide equals;
import 'package:dcli_core/dcli_core.dart' as core;

/// Runs a onepub command on the cli and returns the output
/// stripped of any ansi chars.
List<String> runCmd(String command, {String? workingDirectory}) {
  workingDirectory ??= pwd;
  final pathToRoot = DartProject.self.pathToProjectRoot;
  final pathToOnePub = join(pathToRoot, 'bin', 'onepub.dart');

  final progress = Progress.capture();
  'dart $pathToOnePub $command'.start(
      workingDirectory: workingDirectory, progress: progress, nothrow: true);

  if (progress.exitCode != 0) {
    printerr(progress.toParagraph());
  }

  final clean = <String>[];

  /// strip all of the ansi chars from results to make matching easier.
  for (final result in progress.lines) {
    clean.add(Ansi.strip(result));
  }

  return clean;
}

/// Creates a dart project in a temp directory from one of the
/// test fixtures under test/fixtures. Pass the fixture directory
/// as the [projectName].
Future<void> withTempProject(String projectName,
    Future<void> Function(DartProject dartProject) action) async {
  final pathToRoot = DartProject.self.pathToProjectRoot;
  await core.withTempDir((workingDir) async {
    copyTree(join(pathToRoot, 'test', 'fixtures', projectName), workingDir);

    await action(DartProject.fromPath(workingDir));
  });
}

String pathToOnePubScript = join(DartProject.self.pathToBinDir, 'onepub.dart');
