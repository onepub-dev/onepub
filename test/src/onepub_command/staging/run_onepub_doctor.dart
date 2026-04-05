import 'dart:async';
import 'dart:io';

import 'package:dcli/dcli.dart';
import 'package:path/path.dart';

Future<void> runOnepubDoctor() async {
  final root = DartProject.self.pathToProjectRoot;
  final onepubBin = join(root, 'bin', 'onepub.dart');
  stdout.writeln('Running onepub doctor...');

  final progress = Progress.capture();
  'dart $onepubBin doctor'
      .start(workingDirectory: root, progress: progress, nothrow: true);

  stdout.writeln(progress.toParagraph());
  if (progress.exitCode != 0) {
    throw StateError(
        'onepub doctor failed with exit code ${progress.exitCode}');
  }
}
