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
Register with or accept your invite to onepub.dev at https://onepub.dev/register
Then run: 
  onepub auth

You can then use `opub` in place of `dart pub` or `flutter pub`.

Alternatively you can create the PUB_HOSTED_URL environment variable and continue to use dart pub or flutter pub.
'''));

    print(green('Install of OnePub complete.'));
  }
}
