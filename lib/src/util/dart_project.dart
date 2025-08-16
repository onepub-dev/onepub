import 'package:dcli_core/dcli_core.dart';
import 'package:path/path.dart';

class DartProject {
  static String? findProject(String pathToSearchFrom) {
    var current = truepath(pathToSearchFrom);

    final root = rootPrefix(current);

    // traverse up the directory to find if we are in a traditional directory.
    while (current != root) {
      if (exists(join(current, 'pubspec.yaml'))) {
        return current;
      }
      current = dirname(current);
    }

    return null;
  }
}
