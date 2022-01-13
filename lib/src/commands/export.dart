import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';

import '../exceptions.dart';
import '../onepub_paths.dart';
import '../onepub_settings.dart';
import '../util/credentials.dart';
import '../version/version.g.dart';

///
class ExportCommand extends Command<void> {
  ///
  ExportCommand() {
    argParser.addFlag('secret',
        abbr: 's', help: 'prints the secret to the screen');
  }

  @override
  String get description => 'Exports onepub credentials.';

  @override
  String get name => 'export';

  @override
  void run() {
    export();
  }

  ///
  void export() {
    if (!exists(OnepubPaths().pathToSettingsDir)) {
      createDir(OnepubPaths().pathToSettingsDir, recursive: true);
    }
    final settings = OnepubSettings.load();

    final secret = argResults!['secret'] as bool;

    if (!settings.hasToken) {
      throw ExitException(
          exitCode: 1, message: 'You must run onepub login first.');
    }

    print(orange('Exporting onepub credentials: $packageVersion.'));

    if (secret) {
      print('');
      print('Add the following environment variable to your CI/CD secrets');
      print('');
      print('ONEPUB_SECRET=${settings.onepubToken}');
      print('');
      return;
    } else {
      final path = Credentials.pathToCredentials;
      final to = join(pwd, Credentials.credentialsFileName);
      copy(path, to);

      print('''
Saved credentials to: ${truepath(to)}.

Copy the credentials to your CI/CD environment and run:
onepub import <path to credentials>

''');
    }
  }
}
