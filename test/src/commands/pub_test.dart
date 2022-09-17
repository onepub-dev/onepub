import 'package:dcli/dcli.dart' hide equals;
import 'package:onepub/src/entry_point.dart';
import 'package:onepub/src/my_runner.dart';
import 'package:test/test.dart';

void main() {
  test('pub - missing sub command', () async {
    final progress = await DCliZone().run(
        () async => entrypoint(
              ['pub'],
              CommandSet.onepub,
              'onepub',
            ),
        progress: Progress.capture());

    final firstline = Ansi.strip(progress.lines.first);
    expect(firstline, equals('Missing subcommand for "onepub pub".'));

    expect(progress.lines[2].contains('Available subcommands:'), isTrue);
  });
}
