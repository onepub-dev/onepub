@Tags(['onepub_command', 'unit'])
library;

import 'package:dcli/dcli.dart';
import 'package:onepub/src/entry_point.dart';
import 'package:strings/strings.dart';
import 'package:test/test.dart';

void main() {
  test('pub command without subcommand prints usage', () async {
    final progress = Progress.capture();
    await capture(() async {
      await entrypoint(args: ['pub'], executableName: 'onepub');
    }, progress: progress);

    final clean =
        progress.lines.where(Strings.isNotEmpty).map(Ansi.strip).toList();

    expect(
      clean
          .any((line) => line.contains('Missing subcommand for "onepub pub".')),
      isTrue,
    );
    expect(
      clean.any((line) => line.contains('Usage: onepub pub <subcommand>')),
      isTrue,
    );
  });
}
