import 'package:dcli/dcli.dart' hide equals;
import 'package:onepub/src/entry_point.dart';
import 'package:onepub/src/my_runner.dart';
import 'package:onepub/src/version/version.g.dart';
import 'package:strings_xxx/strings.dart';
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

    final clean =
        progress.lines.where(Strings.isNotEmpty).map(Ansi.strip).toList();
    expect(clean.first, equals('OnePub version: $packageVersion '));
    expect(clean.length, equals(4));
    expect(clean[1], equals('Missing subcommand for "onepub pub".'));

    expect(clean[3].contains('Available subcommands:'), isTrue);
  });
}
