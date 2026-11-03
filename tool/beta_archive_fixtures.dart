#! /usr/bin/env dcli

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:args/args.dart';
import 'package:dcli/dcli.dart' as dcli;

void main(List<String> arguments) {
  final parser = ArgParser()
    ..addOption('output', defaultsTo: '/tmp/onepub-beta-archive-fixtures')
    ..addOption('package', defaultsTo: 'onepub_staging_test_archive_probe')
    ..addOption('version', defaultsTo: '0.0.1')
    ..addFlag('heavy', negatable: false);
  final args = parser.parse(arguments);
  final output = Directory(args['output'] as String);
  final package = args['package'] as String;
  final version = args['version'] as String;
  final heavy = args['heavy'] as bool;
  if (!package.startsWith('onepub_staging_test_') ||
      !RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(package)) {
    throw ArgumentError('Use a disposable onepub_staging_test_ package name.');
  }
  if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version)) {
    throw ArgumentError('Use a simple x.y.z version.');
  }
  output.createSync(recursive: true);
  final pubspec = utf8.encode('''
name: $package
version: $version
description: Controlled beta archive security fixture.
environment:
  sdk: '>=3.5.0 <4.0.0'
''');
  final xssPubspec = utf8.encode('''
name: $package
version: $version
description: 'Controlled <img src=x onerror=window.__onepubPentestCanary=true>'
environment:
  sdk: '>=3.5.0 <4.0.0'
''');

  final firstPubspec = TarEncoder().encodeBytes(
      Archive()..addFile(ArchiveFile.bytes('pubspec.yaml', pubspec)));
  final secondPubspec = TarEncoder().encodeBytes(
      Archive()..addFile(ArchiveFile.bytes('pubspec.yaml', utf8.encode('''
name: $package
version: $version
description: Duplicate pubspec marker from the second archive entry.
environment:
  sdk: '>=3.5.0 <4.0.0'
'''))));
  final cases = <String, List<int>>{
    'traversal': TarEncoder().encodeBytes(Archive()
      ..addFile(ArchiveFile.bytes('pubspec.yaml', pubspec))
      ..addFile(ArchiveFile.bytes('../onepub-pentest-escape.txt', [65]))),
    'symlink': TarEncoder().encodeBytes(Archive()
      ..addFile(ArchiveFile.bytes('pubspec.yaml', pubspec))
      ..addFile(ArchiveFile.symlink('lib/payload.dart', '../../etc/passwd'))),
    'oversized_readme': TarEncoder().encodeBytes(Archive()
      ..addFile(ArchiveFile.bytes('pubspec.yaml', pubspec))
      ..addFile(ArchiveFile.bytes(
          'README.md', List<int>.filled(10 * 1024 * 1024 + 1, 65)))),
    'xss_readme': TarEncoder().encodeBytes(Archive()
      ..addFile(ArchiveFile.bytes('pubspec.yaml', pubspec))
      ..addFile(ArchiveFile.bytes(
          'README.md',
          utf8.encode(
              '# Controlled beta canary\n<script>window.__onepubPentestCanary=true</script>\n')))),
    'xss_description': TarEncoder().encodeBytes(Archive()
      ..addFile(ArchiveFile.bytes('pubspec.yaml', xssPubspec))
      ..addFile(ArchiveFile.bytes(
          'README.md', utf8.encode('# Controlled beta canary\n')))),
    'duplicate_pubspec': [
      ...firstPubspec.sublist(0, firstPubspec.length - 1024),
      ...secondPubspec,
    ],
  };
  if (heavy) {
    final flood = Archive()
      ..addFile(ArchiveFile.bytes('pubspec.yaml', pubspec));
    for (var index = 0; index <= 100000; index++) {
      final name = 'lib/f${index.toString().padLeft(6, '0')}.dart';
      flood.addFile(ArchiveFile.bytes(name, const []));
    }
    cases['entry_flood'] = TarEncoder().encodeBytes(flood);
  }
  for (final entry in cases.entries) {
    final gzip = const GZipEncoder().encodeBytes(entry.value);
    final file = File('${output.path}/${entry.key}.tar.gz')
      ..writeAsBytesSync(gzip, flush: true);
    print('${entry.key}: ${file.path} (${gzip.length} bytes)');
  }
  final runId = dcli.env['ONEPUB_PENTEST_RUN_ID'] ??
      DateTime.now().toUtc().toIso8601String();
  print('Run ID: $runId');
  print('Fixtures are local only. Upload them only to a disposable '
      'beta package.');
}
