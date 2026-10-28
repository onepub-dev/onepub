import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/test_evidence.dart';

void main() {
  test('retains dispositions and timing without arbitrary output or secrets',
      () {
    final evidence = TestEvidence({'sensitive-token'});
    final directory = Directory.systemTemp.createTempSync('evidence-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    for (final event in [
      {
        'type': 'testStart',
        'time': 10,
        'test': {'id': 1, 'suiteID': 0, 'name': 'case sensitive-token'}
      },
      {'type': 'print', 'message': 'unknown-secret'},
      {
        'type': 'error',
        'testID': 1,
        'error': 'another-secret',
        'stackTrace': 'private stack'
      },
      {
        'type': 'testDone',
        'time': 42,
        'testID': 1,
        'result': 'failure',
        'skipped': false,
        'hidden': false
      },
    ]) {
      evidence.addLine(jsonEncode(event));
    }
    evidence.write(directory, exitCode: 1, elapsedMs: 50, candidateFiles: [
      'test/a_test.dart'
    ], discoveredInventory: [
      'test/a_test.dart',
      'test/b_test.dart'
    ], selectionArguments: [
      'test',
      'test/a_test.dart',
      '--exclude-tags',
      'manual'
    ]);
    final output = directory
        .listSync()
        .whereType<File>()
        .map((file) => file.readAsStringSync())
        .join();
    expect(output, isNot(contains('sensitive-token')));
    expect(output, isNot(contains('unknown-secret')));
    expect(output, isNot(contains('another-secret')));
    expect(output, isNot(contains('private stack')));
    expect(output, contains('32'));
    expect(output, contains('<failure'));
    expect(output, contains('test/a_test.dart'));
    final summary =
        jsonDecode(File('${directory.path}/summary.json').readAsStringSync())
            as Map<String, dynamic>;
    expect(
        summary['candidateFilesBeforeTagAndNameFilters'], ['test/a_test.dart']);
    expect(summary['discoveredInventory'], hasLength(2));
    expect(summary['selectionArguments'], contains('--exclude-tags'));
  });

  test('empty, incomplete and omitted file runs cannot pass evidence gate', () {
    final evidence = TestEvidence({});
    expect(evidence.validationErrors([]), isNotEmpty);
    for (final event in [
      {
        'type': 'suite',
        'suite': {'id': 0, 'path': 'test/a_test.dart'}
      },
      {
        'type': 'testStart',
        'time': 1,
        'test': {'id': 1, 'suiteID': 0, 'name': 'assertion'}
      },
      {'type': 'done', 'success': true},
    ]) {
      evidence.addLine(jsonEncode(event));
    }
    expect(evidence.validationErrors(['test/a_test.dart']),
        contains('Test cases did not complete'));
    evidence.addLine(jsonEncode({
      'type': 'testDone',
      'time': 5,
      'testID': 1,
      'hidden': false,
      'skipped': false,
      'result': 'success'
    }));
    expect(evidence.validationErrors(['test/a_test.dart']), isEmpty);
    expect(evidence.validationErrors(['test/a_test.dart', 'test/b_test.dart']),
        contains('Selected test file was not loaded: test/b_test.dart'));
  });
}
