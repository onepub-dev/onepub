import 'dart:io';

import 'package:onepub/src/api/versions.dart';
import 'package:onepub/src/util/one_pub_token_store.dart';
import 'package:path/path.dart';
import 'package:yaml/yaml.dart';

Future<void> pubArchiveTest({
  required JsonVersion versionEntry,
  required String packageName,
  required String version,
}) async {
  stdout.writeln('Downloading archive for $packageName $version...');
  final archiveUrl = versionEntry.archiveUrl;
  if (archiveUrl.isEmpty) {
    throw StateError('Archive URL missing for $packageName $version.');
  }

  final token = await OnePubTokenStore().load();
  final uri = Uri.parse(archiveUrl);

  final tempDir = await Directory.systemTemp.createTemp('onepub_archive_');
  final archivePath = join(tempDir.path, '$packageName-$version.tar.gz');
  final archiveFile = File(archivePath);

  final client = HttpClient();
  final request = await client.getUrl(uri);
  request.headers.set('authorization', token);
  final response = await request.close();
  if (response.statusCode != 200) {
    throw StateError(
        'Archive download failed with status ${response.statusCode}.');
  }

  await response.pipe(archiveFile.openWrite());
  client.close();

  final extractDir = Directory(join(tempDir.path, 'extract'));
  await extractDir.create(recursive: true);

  final extractResult = await Process.run(
    'tar',
    ['-xzf', archivePath, '-C', extractDir.path],
  );
  if (extractResult.exitCode != 0) {
    throw StateError('Archive extract failed: ${extractResult.stderr}');
  }

  final pubspecFile = _findPubspec(extractDir);
  if (pubspecFile == null) {
    throw StateError('pubspec.yaml not found in archive.');
  }

  final pubspec = loadYaml(pubspecFile.readAsStringSync()) as YamlMap;
  final name = pubspec['name'] as String? ?? '';
  final pubspecVersion = pubspec['version'] as String? ?? '';

  if (name != packageName) {
    throw StateError(
        'Archive pubspec name mismatch: expected $packageName, got $name.');
  }
  if (pubspecVersion != version) {
    throw StateError('''
Archive pubspec version mismatch: expected $version, got $pubspecVersion.''');
  }
}

File? _findPubspec(Directory root) {
  final direct = File(join(root.path, 'pubspec.yaml'));
  if (direct.existsSync()) {
    return direct;
  }
  for (final entry in root.listSync(recursive: true)) {
    if (entry is File && basename(entry.path) == 'pubspec.yaml') {
      return entry;
    }
  }
  return null;
}
