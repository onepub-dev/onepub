import 'package:args/command_runner.dart';

/// provides actions on a package
///
/// onepub package create <package> <team>

class PackageCommand extends Command<void> {
  ///
  PackageCommand();

  @override
  String get description => 'Maintain packages.';

  @override
  String get name => 'package';
}
