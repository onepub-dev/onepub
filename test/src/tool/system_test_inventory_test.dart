import 'package:test/test.dart';

import '../../../tool/system_test_inventory.dart';

void main() {
  test('untagged and new files are retained exactly once in serial lane', () {
    final files = [
      'test/test_settings_test.dart',
      'test/new_untagged_test.dart',
      'test/src/onepub_command/staging/staging_publish_test.dart'
    ];
    final result = partitionTestFiles(files);
    expect(result.independent, ['test/test_settings_test.dart']);
    expect(result.serial, files.skip(1));
    expect([...result.independent, ...result.serial], unorderedEquals(files));
  });
}
