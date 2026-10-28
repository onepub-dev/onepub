import 'package:test/test.dart';

import '../onepub_command/staging/shared_publish_fixture.dart';

void main() {
  test('all optional combinations retain publish and their exact consumers',
      () {
    for (var mask = 0; mask < 32; mask++) {
      final skipPublish = mask & 1 != 0;
      final selected = publishJourneySelection(
          skipPublish: skipPublish,
          skipMetadata: mask & 2 != 0,
          skipArchive: mask & 4 != 0,
          skipPubGet: mask & 8 != 0,
          skipCleanup: mask & 16 != 0);
      expect(selected['publish package'], !skipPublish);
      final consumers = [
        'pub metadata',
        'pub archive',
        'pub get',
        'cleanup package'
      ];
      for (var i = 0; i < consumers.length; i++) {
        expect(selected[consumers[i]], !skipPublish && mask & (2 << i) == 0);
      }
    }
  });
  test('assertions reuse setup; deletion and filtered cases remain independent',
      () async {
    final fixture = SharedPublishFixture<int>();
    var publications = 0;
    Future<int> publish() async => ++publications;
    expect(await fixture.get(publish), 1); // standalone deletion preparation
    fixture.deleted();
    expect(await fixture.get(publish), 2); // shuffled metadata after deletion
    expect(await fixture.get(publish), 2); // archive
    expect(await fixture.get(publish), 2); // pub get
    expect(publications, 2);
    expect(await SharedPublishFixture<int>().get(publish), 3); // filtered case
  });
  test('failed setup is not cached as successful publication', () async {
    final fixture = SharedPublishFixture<int>();
    await expectLater(
        fixture.get(() async => throw StateError('publish failed')),
        throwsStateError);
    expect(await fixture.get(() async => 42), 42);
  });
}
