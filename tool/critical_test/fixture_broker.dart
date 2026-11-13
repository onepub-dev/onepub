#! /usr/bin/env dcli

import 'dart:convert';
import 'dart:io';

import 'package:dcli/posix.dart' show chmod;
import 'package:path/path.dart' as p;

import '../../test/fixture_oauth.dart';

/// Runs in the CLI package, independently of the deployment package graph.
/// Parent pipe closure also shuts down the broker if the fixture host exits.
Future<void> main(List<String> args) async {
  FixtureOAuthBroker? broker;
  File? handoff;
  try {
    if (args.length != 1) {
      throw ArgumentError('Expected private fixture state.');
    }
    final state = Directory(args.single);
    await FixtureOAuth.requirePrivateState(state);
    final seed = jsonDecode(
      Platform.environment[FixtureOAuth.authorizationKey] ?? '',
    ) as Map<String, dynamic>;
    broker = await FixtureOAuth.startHarness(
      seed['onepubUrl'] as String,
      authorization: seed,
    );
    final published = p.join(state.path, 'broker.json');
    if (FileSystemEntity.typeSync(published, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw StateError('A fixture broker handoff already exists.');
    }
    handoff = File(p.join(state.path, 'broker.json.pending'))
      ..createSync(exclusive: true);
    chmod(handoff.path, permission: '600');
    await handoff.writeAsString(
      jsonEncode({
        'origin': seed['onepubUrl'],
        'broker': broker.workerEnvironment({})[FixtureOAuth.brokerKey],
      }),
      flush: true,
    );
    handoff = await handoff.rename(published);
    await stdin.drain<void>();
  } on Object {
    stderr.writeln('Local fixture OAuth broker failed.');
    exitCode = 1;
  } finally {
    await broker?.close();
    if (handoff != null && handoff.existsSync()) {
      await handoff.delete();
    }
  }
}
