import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dcli/dcli.dart';
import 'package:dcli_core/dcli_core.dart' as core;
import 'package:onepub/src/api/cli_models.dart';
import 'package:onepub/src/util/one_pub_token_store.dart';
import 'package:onepub/src/util/send_command.dart';
import 'package:path/path.dart';

import 'publish_result.dart';

Future<PublishResult> publishTestPackage({
  required String packagePrefix,
  required String apiUrl,
  required String? team,
  required bool skipPackageCreate,
  int largeNativeAssetBytes = 0,
}) async {
  final suffix = DateTime.now().toUtc().millisecondsSinceEpoch;
  final packageName = '${packagePrefix}_$suffix';
  final version = '0.0.1-dev.$suffix';

  stdout.writeln('Publishing $packageName $version...');

  if (!skipPackageCreate) {
    if (team == null || team.isEmpty) {
      await _listTeamsAndExit();
    }
    await _ensurePackageCreated(packageName, team);
  }

  await core.withTempDirAsync((tempDir) async {
    final libDir = join(tempDir, 'lib');
    createDir(libDir, recursive: true);

    File(join(tempDir, 'pubspec.yaml')).writeAsStringSync('''
name: $packageName
description: OnePub staging publish test package.
version: $version
homepage: https://onepub.dev
publish_to: $apiUrl
environment:
  sdk: '>=3.5.0 <4.0.0'
''');

    File(join(libDir, '$packageName.dart')).writeAsStringSync('''
library $packageName;

String onepubStagingTest() => '$packageName:$version';
''');
    File(join(tempDir, 'README.md')).writeAsStringSync('''
# $packageName

OnePub staging publish test package.
''');
    File(join(tempDir, 'CHANGELOG.md')).writeAsStringSync('''
## $version

- Initial staging test publish.
''');
    File(join(tempDir, 'LICENSE')).writeAsStringSync('''
OnePub License
Copyright (c) 2025 OnePub
''');

    if (largeNativeAssetBytes > 0) {
      final nativeDir = join(tempDir, 'native');
      createDir(nativeDir, recursive: true);
      final assetPath = join(nativeDir, 'large_asset.bin');
      await _writeRandomAsset(assetPath, largeNativeAssetBytes);
      stdout.writeln(
          'Created native asset $assetPath ($largeNativeAssetBytes bytes).');
    }

    final publishToken = await OnePubTokenStore().load();
    const publishTokenEnv = 'ONEPUB_PUBLISH_TOKEN';
    final pubHomeDir = join(tempDir, '.dart_tool', 'pub_home');
    final pubConfigRoot = join(tempDir, '.dart_tool', 'pub_config');
    createDir(pubHomeDir, recursive: true);
    createDir(pubConfigRoot, recursive: true);
    final publishEnv = {
      publishTokenEnv: publishToken,
      'HOME': pubHomeDir,
      'XDG_CONFIG_HOME': pubConfigRoot,
    };

    final tokenProgress = Progress.capture();
    await core.withEnvironmentAsync(
      () async {
        '${Platform.resolvedExecutable} pub token add $apiUrl '
                '--env-var $publishTokenEnv'
            .start(
          workingDirectory: tempDir,
          progress: tokenProgress,
          nothrow: true,
        );
      },
      environment: publishEnv,
    );
    if (tokenProgress.exitCode != 0) {
      throw StateError('''
dart pub token add failed for $apiUrl (exit code ${tokenProgress.exitCode})
raw output:
${tokenProgress.toParagraph()}''');
    }

    final progress = Progress.capture();
    await core.withEnvironmentAsync(
      () async {
        '${Platform.resolvedExecutable} pub publish --force'.start(
          workingDirectory: tempDir,
          progress: progress,
          nothrow: true,
        );
      },
      environment: publishEnv,
    );
    final publishOutput = progress.toParagraph();
    stdout.writeln(publishOutput);
    if (progress.exitCode != 0) {
      if (publishOutput.contains('must create the package first')) {
        stderr.writeln('''
Publish failed because the package is not assigned to a team. 
Create the package in the OnePub UI and assign it to a team, then retry.''');
      }
      stderr.writeln('''
dart pub publish failed for $packageName (exit code ${progress.exitCode})
publish_to: $apiUrl
team: ${team ?? '<none>'}
raw output:
$publishOutput''');
      throw StateError(
          'dart pub publish failed with exit code ${progress.exitCode}');
    }
  });

  return PublishResult(packageName, version);
}

Future<void> _writeRandomAsset(String path, int bytes) async {
  final file = File(path);
  final sink = file.openWrite();
  final random = Random();
  const chunkSize = 64 * 1024;
  var remaining = bytes;
  try {
    while (remaining > 0) {
      final toWrite = remaining > chunkSize ? chunkSize : remaining;
      final chunk = List<int>.generate(toWrite, (_) => random.nextInt(256));
      sink.add(chunk);
      remaining -= toWrite;
    }
  } finally {
    await sink.close();
  }
}

Future<void> _ensurePackageCreated(String packageName, String? team) async {
  final teamName = team?.trim() ?? '';
  if (teamName.isEmpty) {
    throw StateError('Missing team name; pass --team <team-name>.');
  }

  stdout.writeln('Creating package $packageName for team $teamName...');
  final encodedTeam = Uri.encodeQueryComponent(teamName);
  const maxAttempts = 5;
  EndpointResponse response;
  var attempt = 0;
  while (true) {
    attempt++;
    response = await sendCommand(
      command: 'test/package/create/$packageName?team=$encodedTeam',
      commandType: CommandType.cli,
      method: Method.post,
    );
    if (response.success) {
      return;
    }
    if (response.status == HttpStatus.tooManyRequests &&
        attempt < maxAttempts) {
      final backoffMs = 500 * attempt;
      stderr.writeln('''
Warning: package create hit HTTP 429 on attempt $attempt of $maxAttempts for
package "$packageName"; retrying with attempt ${attempt + 1} in ${backoffMs}ms...''');
      await Future<void>.delayed(Duration(milliseconds: backoffMs));
      continue;
    }
    break;
  }

  if (!response.success) {
    final message = response.errorMessage.trim();
    if (response.status == HttpStatus.tooManyRequests) {
      throw StateError(
          'Package create failed (HTTP 429) after $maxAttempts attempts. '
          'Rate limited by server; retry later.');
    }
    if (response.status == HttpStatus.forbidden) {
      throw StateError(
          'Package create failed (HTTP 403): you are not permitted to create '
          'a package for team "$teamName". Ensure this token is a member of '
          'that team (or set ONEPUB_TEAM to a team the token belongs to). '
          'Server message: $message');
    }
    if (response.status == HttpStatus.badRequest && message.isNotEmpty) {
      throw StateError('Package create failed (HTTP 400): $message '
          '(team="$teamName").');
    }
    if (message.isNotEmpty && message != 'Empty response') {
      throw StateError(
          'Package create failed (HTTP ${response.status}): $message');
    }
    throw StateError(
        'Package create failed (HTTP ${response.status}) with empty server '
        'message. Check team membership for "$teamName" and test-endpoint '
        'access.');
  }
}

Future<void> _listTeamsAndExit() async {
  stdout.writeln('Listing teams via test endpoint...');
  final response = await sendCommand(
    command: 'test/team/list',
    commandType: CommandType.cli,
  );

  if (response.success) {
    final envelope = response.parseCli(CliTeamListBody.fromJson);
    final teams = envelope.body?.teams ?? <CliTeamInfo>[];
    if (teams.isEmpty) {
      stderr.writeln('No teams returned; cannot select a team for publishing.');
    } else {
      stdout.writeln('Available teams:');
      for (final entry in teams) {
        final name = entry.name;
        final leader = entry.leader ? ' (leader)' : '';
        final everyone = entry.everyoneTeam ? ' (everyone)' : '';
        stdout.writeln(' - $name$leader$everyone');
      }
    }
  } else {
    stderr.writeln('Failed to list teams: ${response.errorMessage}');
  }
  throw StateError('Pass --team <team-name> to continue.');
}
