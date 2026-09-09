import 'dart:io';

import 'package:onepub/src/api/api.dart';
import 'package:onepub/src/api/cli_models.dart';
import 'package:onepub/src/onepub_settings.dart';
import 'package:onepub/src/util/one_pub_token_store.dart';
import 'package:onepub/src/util/send_command.dart';
import 'package:path/path.dart' as p;

import '../test/test_settings.dart';

/// Creates the empty package for the isolated build's GitHub publishing test.
Future<void> main(List<String> args) async {
  Directory? temp;
  try {
    final verify = args.length == 3 && args[2] == '--verify';
    if ((!verify && args.length != 2) ||
        !RegExp(r'^onepub_test_trusted_[a-f0-9]+$').hasMatch(args[1])) {
      throw ArgumentError(
          'Expected a local test URL and generated package name.');
    }
    final url =
        assertSafeOnePubTestUrl(args[0], source: 'trusted test bootstrap');
    if (Uri.parse(url).host != '127.0.0.1') {
      throw ArgumentError(
          'The build bootstrap requires its isolated loopback stack.');
    }
    final token = Platform.environment['ONEPUB_BOOTSTRAP_TEST_TOKEN'];
    if (token == null || token.isEmpty) {
      throw StateError('Missing isolated test bootstrap token.');
    }
    temp = Directory.systemTemp.createTempSync('onepub-trusted-bootstrap-');
    await OnePubSettings.withPathTo(p.join(temp.path, 'settings'), () async {
      final settings = OnePubSettings.use()..onepubUrl = url;
      final org = await API().fetchOrganisation(token);
      if (!org.success) {
        throw StateError(org.errorMessage ?? 'Cannot read test organisation.');
      }
      settings.obfuscatedOrganisationId = org.obfuscatedId!;
      await OnePubTokenStore.withPathTo(p.join(temp!.path, 'tokens'), () async {
        await OnePubTokenStore().addToken(
            onepubApiUrl: settings.onepubApiUrlAsString, onepubToken: token);
        if (verify) {
          final versions =
              await API().fetchVersions(org.obfuscatedId!, args[1]);
          final expectedVersions =
              (Platform.environment['ONEPUB_E2E_EXPECTED_VERSIONS'] ?? '1.0.0')
                  .split(',');
          if (expectedVersions.isEmpty ||
              expectedVersions.any(
                  (version) => !const ['1.0.0', '1.0.1'].contains(version))) {
            throw StateError('Invalid expected test package versions.');
          }
          if (versions.versions.length != expectedVersions.length) {
            throw StateError(
                'Published versions do not match the isolated test.');
          }
          for (final expectedVersion in expectedVersions) {
            final published = versions.versions
                .singleWhere((version) => version.version == expectedVersion);
            final archive = assertSafeOnePubTestUrl(published.archiveUrl,
                source: 'trusted test published archive');
            if (Uri.parse(archive).origin != Uri.parse(url).origin) {
              throw StateError('Archive is not on the isolated test stack.');
            }
            await verifyPublishedArchive(Uri.parse(archive), token);
          }
          stdout.writeln('Verified published package and archive.');
          return;
        }
        final teams = (await sendCommand(
          command: 'test/team/list',
          commandType: CommandType.cli,
          timeout: const Duration(seconds: 15),
        ))
            .requireCliBody(CliTeamListBody.fromJson)
            .teams;
        final team = teams.firstWhere((team) => team.everyoneTeam);
        final result = await sendCommand(
          command:
              'test/package/create/${args[1]}?team=${Uri.encodeQueryComponent(team.name)}',
          commandType: CommandType.cli,
          method: Method.post,
          timeout: const Duration(seconds: 15),
        );
        if (!result.success) {
          throw StateError(result.errorMessage);
        }
      });
    });
  } on Object catch (e) {
    stderr.writeln('Trusted publishing test setup failed: $e');
    exitCode = 1;
  } finally {
    temp?.deleteSync(recursive: true);
  }
}

/// The authenticated archive route redirects to a temporary download grant.
/// Keep every request on the isolated origin and send the bootstrap token only
/// to the original route. Do not print grant URLs or response bodies.
Future<void> verifyPublishedArchive(Uri archive, String token) async {
  final client = HttpClient();
  try {
    await _downloadArchive(client, archive, token)
        .timeout(const Duration(seconds: 30));
  } finally {
    client.close(force: true);
  }
}

Future<void> _downloadArchive(
    HttpClient client, Uri archive, String token) async {
  var current = archive;
  for (var redirects = 0; redirects <= 5; redirects++) {
    final request = await client.getUrl(current);
    request.followRedirects = false;
    if (redirects == 0) {
      request.headers.set(HttpHeaders.authorizationHeader, token);
    }
    final response = await request.close();
    if (const [301, 302, 303, 307, 308].contains(response.statusCode)) {
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (location == null || location.isEmpty) {
        throw StateError('Published archive redirect has no location.');
      }
      final Uri next;
      try {
        next = current.resolve(location);
      } on FormatException {
        throw StateError('Published archive redirect is invalid.');
      }
      if (!const ['http', 'https'].contains(next.scheme) ||
          next.origin != archive.origin ||
          next.userInfo.isNotEmpty) {
        throw StateError('Archive redirect is not on the isolated test stack.');
      }
      await response.drain<void>();
      current = next;
      continue;
    }
    if (response.statusCode != HttpStatus.ok) {
      throw StateError(
          'Published archive download failed (HTTP ${response.statusCode}).');
    }
    final bytes = await response.fold<int>(
      0,
      (sum, bytes) => sum + bytes.length,
    );
    if (bytes == 0) {
      throw StateError('Published archive is empty.');
    }
    return;
  }
  throw StateError('Published archive exceeded the redirect limit.');
}
