#! /usr/bin/env dcli

import 'dart:convert';
import 'dart:io';

const betaHost = 'beta.onepub.dev';
const int maxInspectedBytes = 256 * 1024;
const paths = <String>[
  '/.env',
  '/.env.production',
  '/.git/HEAD',
  '/.git/config',
  '/.svn/entries',
  '/.aws/credentials',
  '/config/settings.yaml',
  '/opt/onepub/config/settings.yaml',
  '/settings.yaml',
  '/application.properties',
  '/WEB-INF/web.xml',
  '/META-INF/MANIFEST.MF',
  '/actuator/env',
  '/actuator/heapdump',
  '/actuator/configprops',
  '/actuator/health',
  '/metrics',
  '/prometheus',
  '/swagger-ui/',
  '/v3/api-docs',
  '/mailhog/',
  '/backup/',
  '/backup.zip',
  '/dump.sql',
  '/logs/',
  '/server-status',
  '/debug/pprof/',
  '/api_docs/private/unknown/onepub_staging_test_unknown/0.0.1/index.html',
];
const secretMarkers = <String>[
  '-----BEGIN PRIVATE KEY-----',
  'CLOUDFLARE_API_TOKEN',
  'AIR_WALLEX_WEB_HOOK_KEY',
  'MYSQL_PASSWORD',
  'BREAD_BUTTER_APP_SECRET',
];

Future<void> main() async {
  print('Beta surface path sweep: ${DateTime.now().toUtc().toIso8601String()}');
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5)
    ..maxConnectionsPerHost = 4;
  var reviewed = 0;
  try {
    for (final path in paths) {
      final uri = Uri.https(betaHost, path);
      if (uri.scheme != 'https' || uri.host != betaHost) {
        throw StateError('Target guard failed.');
      }
      try {
        final request =
            await client.getUrl(uri).timeout(const Duration(seconds: 8));
        request.followRedirects = false;
        request.headers.set(
            HttpHeaders.userAgentHeader, 'OnePub-beta-authorized-pentest/1.0');
        final response =
            await request.close().timeout(const Duration(seconds: 12));
        final bytes = <int>[];
        await for (final chunk
            in response.timeout(const Duration(seconds: 12))) {
          if (bytes.length < maxInspectedBytes) {
            bytes.addAll(chunk.take(maxInspectedBytes - bytes.length));
          }
          if (bytes.length >= maxInspectedBytes) {
            break;
          }
        }
        final type = response.headers.contentType?.mimeType ?? 'unknown';
        final body = utf8.decode(bytes, allowMalformed: true);
        final shell = type == 'text/html' &&
            body.trimLeft().toLowerCase().startsWith('<!doctype html');
        final markers = secretMarkers.any(body.contains);
        final redirect = response.headers.value(HttpHeaders.locationHeader);
        final escaped = redirect != null &&
            Uri.parse(redirect).hasAuthority &&
            Uri.parse(redirect).host != betaHost;
        final exposed =
            markers || escaped || (response.statusCode == 200 && !shell);
        print('$path: ${response.statusCode} $type shell=$shell '
            'secret-marker=$markers external-redirect=$escaped '
            'review=$exposed');
        if (exposed) {
          reviewed++;
        }
      } catch (error) {
        print('$path: ERROR ${error.runtimeType}');
        reviewed++;
      }
    }
  } finally {
    client.close(force: true);
  }
  print('Paths requiring review: $reviewed/${paths.length}');
  if (reviewed > 0) {
    exitCode = 2;
  }
}
