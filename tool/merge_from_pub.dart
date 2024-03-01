import 'package:dcli/dcli.dart' as dcli;
import 'package:dcli_core/dcli_core.dart';
import 'package:path/path.dart';

void main() {
  final projectRoot = dcli.DartProject.self.pathToProjectRoot;
  final onepubSrc = dcli.DartProject.self.pathToLibSrcDir;
  final pubTarget = join(onepubSrc, 'pub');
  final pubSrcRoot = join(projectRoot, '..', '..', 'pub', 'lib', 'src');

  copyTree(pubSrcRoot, pubTarget, overwrite: true);

  // copyPubDir(pubSrcRoot, pubTarget, 'authentication');
  // copyPubDir(pubSrcRoot, pubTarget, 'command');
  // copyPubDir(pubSrcRoot, pubTarget, 'sdk');
  // copyPubDir(pubSrcRoot, pubTarget, 'solver');
  // copyPubDir(pubSrcRoot, pubTarget, 'source');
  // copyPubDir(pubSrcRoot, pubTarget, 'third_party');
  // copyPubDir(pubSrcRoot, pubTarget, 'validator');
}

// void copyPubDir(String pubSrcRoot, String pubTarget, String dir) {
//   copyTree(join(pubSrcRoot, dir), join(pubTarget, dir));
// }
