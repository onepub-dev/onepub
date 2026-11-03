@Tags(['onepub_command', 'integration', 'staging'])
library;

import 'dart:io';

import 'package:onepub/src/util/one_pub_token_store.dart';
import 'package:test/test.dart';

import 'cleanup_package.dart';
import 'staging_common.dart';

Uri _sameOrigin(Uri origin, String url) {
  final target = origin.resolve(url);
  if (target.scheme != origin.scheme ||
      target.host != origin.host ||
      target.port != origin.port) {
    throw StateError('Download URL left the configured staging origin.');
  }
  return target;
}

Future<HttpClientResponse> _get(HttpClient client, Uri uri,
    {String? token}) async {
  final request = await client.getUrl(uri).timeout(const Duration(seconds: 10));
  request.followRedirects = false;
  if (token != null) {
    request.headers.set(HttpHeaders.authorizationHeader, token);
  }
  final response = await request.close().timeout(const Duration(seconds: 30));
  await response.drain<void>().timeout(const Duration(seconds: 30));
  return response;
}

Future<Uri> _issueGrant(
    HttpClient client, Uri origin, Uri archive, String token) async {
  final response = await _get(client, archive, token: token);
  if (response.statusCode != HttpStatus.temporaryRedirect) {
    throw StateError('Expected archive grant redirect; got '
        '${response.statusCode}.');
  }
  final location = response.headers.value(HttpHeaders.locationHeader);
  if (location == null) {
    throw StateError('Archive grant redirect had no Location header.');
  }
  final grant = _sameOrigin(origin, location);
  if (!grant.path.startsWith('/api_download/private/')) {
    throw StateError('Archive redirect did not issue a private grant.');
  }
  return grant;
}

void main() {
  final config = StagingConfig.fromEnv();
  setUpAll(() => ensureTestUsers(config));

  test('private archive grants reject changed keys and replay', () async {
    await withAdmin(config, (context) async {
      final published = await publishAndVerify(context, config);
      try {
        final origin = Uri.parse(config.stagingUrl);
        final archiveUrl = published.versionsBody.versions
            .firstWhere((version) => version.version == published.version)
            .archiveUrl;
        final archive = _sameOrigin(origin, archiveUrl);
        final token = await OnePubTokenStore().load();
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 10);
        try {
          final grant = await _issueGrant(client, origin, archive, token);
          final parts = grant.pathSegments.toList();
          if (parts.length < 4 ||
              parts[0] != 'api_download' ||
              parts[1] != 'private') {
            throw StateError('Unexpected private grant path.');
          }
          parts[2] = '${parts[2]}x';
          final changedKey = grant.replace(pathSegments: parts);
          expect(
              (await _get(client, changedKey)).statusCode, HttpStatus.notFound);
          expect((await _get(client, grant)).statusCode, HttpStatus.ok);
          expect((await _get(client, grant)).statusCode, HttpStatus.notFound);

          final racingGrant = await _issueGrant(client, origin, archive, token);
          final race = await Future.wait([
            _get(client, racingGrant),
            _get(client, racingGrant),
          ]);
          final statuses = race.map((response) => response.statusCode).toList()
            ..sort();
          expect(statuses, [HttpStatus.ok, HttpStatus.notFound]);
        } finally {
          client.close(force: true);
        }
      } finally {
        await cleanupPackage(published.name);
      }
    });
  },
      timeout: const Timeout(Duration(minutes: 10)),
      skip: config.skipArchiveTest || config.skipPublish);
}
