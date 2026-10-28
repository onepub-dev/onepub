import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Stores only test protocol fields; arbitrary test prints, exception messages,
/// stack traces and environment variables may contain secrets and are omitted.
class TestEvidence {
  final List<Map<String, Object?>> events = [];
  final Map<int, Map<String, Object?>> cases = {};
  final Set<String> secrets;
  final String rootDirectory;
  final Set<String> observedSuiteFiles = {};
  var completedSuccessfully = false;

  TestEvidence(this.secrets, {String? rootDirectory})
      : rootDirectory = rootDirectory ?? Directory.current.path;

  String _absolute(String path) =>
      p.normalize(p.isAbsolute(path) ? path : p.join(rootDirectory, path));

  String sanitize(String value) {
    var result = value;
    for (final secret in secrets.where((value) => value.isNotEmpty)) {
      result = result.replaceAll(secret, '[redacted]');
    }
    return result;
  }

  void addLine(String line) {
    Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, dynamic>) {
      return;
    }
    final type = decoded['type'];
    final event = <String, Object?>{'type': type, 'time': decoded['time']};
    if (type == 'suite') {
      final suite = decoded['suite'] as Map<String, dynamic>;
      final path = suite['path'];
      if (path is String) {
        observedSuiteFiles.add(_absolute(path));
        event['path'] = sanitize(path);
        event['suiteID'] = suite['id'];
      }
    } else if (type == 'testStart') {
      final test = decoded['test'] as Map<String, dynamic>;
      final id = test['id'] as int;
      final value = <String, Object?>{
        'id': id,
        'name': sanitize(test['name'] as String),
        'suiteID': test['suiteID'],
        'startMs': decoded['time'],
      };
      cases[id] = value;
      event['test'] = value;
    } else if (type == 'testDone') {
      for (final key in ['testID', 'result', 'skipped', 'hidden']) {
        event[key] = decoded[key];
      }
      final value = cases[decoded['testID']];
      if (value != null) {
        value.addAll(event);
        value['elapsedMs'] =
            (decoded['time'] as int) - (value['startMs']! as int);
      }
    } else if (type == 'error') {
      event['testID'] = decoded['testID'];
      event['isFailure'] = decoded['isFailure'];
    } else if (type == 'done') {
      event['success'] = decoded['success'];
      completedSuccessfully = decoded['success'] == true;
    } else {
      return;
    }
    events.add(Map<String, Object?>.from(event));
  }

  List<String> validationErrors(List<String> candidateFiles) => [
        if (!completedSuccessfully) 'Missing successful final test event',
        if (!cases.values.any((value) =>
            value['hidden'] == false &&
            value['skipped'] != true &&
            value['result'] == 'success'))
          'No completed executable test cases',
        for (final file in candidateFiles)
          if (!observedSuiteFiles.contains(_absolute(file)))
            'Selected test file was not loaded: $file',
        if (cases.values.any((value) => !value.containsKey('result')))
          'Test cases did not complete',
      ];

  void write(Directory directory,
      {required int exitCode,
      required int elapsedMs,
      required List<String> candidateFiles,
      required List<String> discoveredInventory,
      required List<String> selectionArguments}) {
    directory.createSync(recursive: true);
    File('${directory.path}/events.jsonl')
        .writeAsStringSync(events.map(jsonEncode).join('\n'));
    File('${directory.path}/summary.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
      'exitCode': exitCode,
      'elapsedMs': elapsedMs,
      'candidateFilesBeforeTagAndNameFilters': candidateFiles,
      'discoveredInventory': discoveredInventory,
      'selectionArguments': selectionArguments.map(sanitize).toList(),
      'observedSuiteFiles': observedSuiteFiles.toList(),
      'validationErrors': validationErrors(candidateFiles),
      'cases': cases.values.toList(),
      'omittedFields': ['print', 'error message', 'stack trace', 'environment'],
    }));
    String xml(String value) => sanitize(value)
        .replaceAll('&', '&amp;')
        .replaceAll('"', '&quot;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
    final output = StringBuffer('<?xml version="1.0"?><testsuite>');
    for (final value
        in cases.values.where((value) => value['hidden'] != true)) {
      output.write('<testcase name="${xml(value['name']! as String)}" '
          'time="${((value['elapsedMs'] as int?) ?? 0) / 1000}">');
      if (value['skipped'] == true) {
        output.write('<skipped/>');
      } else if (value['result'] != 'success') {
        output.write('<failure message="Test failed or did not complete; '
            'inspect local console"/>');
      }
      output.write('</testcase>');
    }
    output.write('</testsuite>');
    File('${directory.path}/junit.xml').writeAsStringSync(output.toString());
  }
}
