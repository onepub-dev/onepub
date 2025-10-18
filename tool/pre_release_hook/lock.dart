import 'package:dcli/dcli.dart';

/// Lock the pubspec.yaml file dependency versions so that they
/// will always install the same versions we test against.
void main() => 'dcli lock'.run;
