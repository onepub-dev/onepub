import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';

import '../onepub_paths.dart';
import '../onepub_settings.dart';
import '../version/version.g.dart';
import 'config.dart';

///
class InstallCommand extends Command<void> {
  ///
  InstallCommand();

  @override
  String get description => 'Installs onepub.';

  @override
  String get name => 'install';

  @override
  void run() {
    install();
  }

  ///
  void install() {
    if (!exists(OnePubPaths().pathToSettingsDir)) {
      createDir(OnePubPaths().pathToSettingsDir, recursive: true);
    }
    OnePubSettings.load();

    print(orange('Installing OnePub version: $packageVersion.'));

    if (!exists(OnePubPaths().pathToSettingsDir)) {
      createDir(OnePubPaths().pathToSettingsDir, recursive: true);
    }

    ConfigCommand().config(dev: false);

    print(blue('''
Register with or accept your invite to onepub.dev at https://${OnePubSettings.onepubHostName}/Register
Then run: 
  onepub login

You can then use `opub` in place of `dart pub` or `flutter pub`.

'''));

    print(green('Install of OnePub complete.'));
  }
}
