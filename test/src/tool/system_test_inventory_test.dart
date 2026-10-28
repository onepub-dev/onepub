import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/system_test_inventory.dart';
import '../../../tool/test_evidence.dart';

void main() {
  for (final positiveFilter in [false, true]) {
    test(
        'runner evidence preserves tag exclusions and positive filters: '
        '$positiveFilter', () async {
      final root = Directory.systemTemp.createTempSync('test-selection-');
      addTearDown(() => root.deleteSync(recursive: true));
      final sources = {
        'manual_test.dart': '''
@Tags(['manual'])
library;
import 'package:test/test.dart';
void main() { test('manual case', () => fail('must remain excluded')); }
''',
        'active_test.dart': '''
// @Tags(['manual']) must not affect selection.
import 'package:test/test.dart';
void main() { test('selected case', () => expect(1, 1), tags: ['unit']); }
''',
        'filtered_test.dart': '''
import 'package:test/test.dart';
void main() {
  test('other case', () => expect(1, 1), tags: ['unit']);
  test('case-level manual', () => fail('excluded'), tags: ['manual']);
}
''',
      };
      for (final entry in sources.entries) {
        File('${root.path}/${entry.key}').writeAsStringSync(entry.value);
      }
      final arguments = [
        'test',
        '--reporter=json',
        '--exclude-tags',
        'manual',
        if (positiveFilter) ...['--plain-name', 'selected', '--tags', 'unit'],
        ...sources.keys.map((path) => '${root.path}/$path'),
      ];
      final effective = effectiveTestInventory(
          root.path, sources.keys.toList(), arguments, 'manual');
      expect(
          effective.requiredFiles, ['active_test.dart', 'filtered_test.dart']);
      expect(effective.excludedFiles, {
        'manual_test.dart': ['manual']
      });
      final process = await Process.run(Platform.resolvedExecutable, arguments);
      expect(process.exitCode, 0, reason: process.stderr.toString());
      final evidence = TestEvidence({}, rootDirectory: root.path);
      const LineSplitter()
          .convert(process.stdout.toString())
          .forEach(evidence.addLine);
      expect(evidence.validationErrors(effective.requiredFiles), isEmpty);
      evidence.write(Directory('${root.path}/evidence'),
          exitCode: process.exitCode,
          elapsedMs: 1,
          candidateFiles: sources.keys.toList(),
          requiredFiles: effective.requiredFiles,
          excludedFiles: effective.excludedFiles,
          discoveredInventory: sources.keys.toList(),
          selectionArguments: arguments);
      final summary = jsonDecode(
              File('${root.path}/evidence/summary.json').readAsStringSync())
          as Map<String, dynamic>;
      expect(summary['candidateFilesBeforeTagAndNameFilters'],
          sources.keys.toList());
      expect(summary['excludedBeforeLoadingByLibraryTags'], {
        'manual_test.dart': ['manual']
      });
      expect(summary['requiredLoadedFiles'], effective.requiredFiles);
      expect(summary['validationErrors'], isEmpty);
      expect(
          evidence.validationErrors([...effective.requiredFiles, 'lost.dart']),
          contains('Selected test file was not loaded: lost.dart'));
      expect(evidence.validationErrors(sources.keys.toList()),
          contains('Selected test file was not loaded: manual_test.dart'));
      final onlyManual = effectiveTestInventory(
          root.path, ['manual_test.dart'], arguments, 'manual');
      expect(onlyManual.requiredFiles, isEmpty);
      expect(TestEvidence({}).validationErrors(onlyManual.requiredFiles),
          contains('No completed executable test cases'));
    });
  }

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
