#! /usr/bin/env dcli

import 'dart:io';

import 'package:args/args.dart';
import 'package:dcli/dcli.dart' as dcli;
import 'package:onepub/src/util/one_pub_token_store.dart';

const betaHost = 'beta.onepub.dev';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('file')
    ..addOption('package', mandatory: true)
    ..addOption('version', defaultsTo: '0.0.1')
    ..addOption('team', defaultsTo: 'everyone')
    ..addOption('expect', defaultsTo: 'reject', allowed: ['reject', 'accept'])
    ..addOption('completion-timeout', defaultsTo: '30')
    ..addFlag('keep', negatable: false)
    ..addFlag('cleanup-only', negatable: false);
  final args = parser.parse(arguments);
  final cleanupOnly = args['cleanup-only'] as bool;
  final keep = args['keep'] as bool;
  final filePath = args['file'] as String?;
  final package = args['package'] as String;
  final version = args['version'] as String;
  final team = args['team'] as String;
  final expect = args['expect'] as String;
  final completionTimeout = int.tryParse(args['completion-timeout'] as String);
  if (completionTimeout == null ||
      completionTimeout < 10 ||
      completionTimeout > 300) {
    throw ArgumentError('--completion-timeout must be 10..300 seconds.');
  }
  if (!cleanupOnly &&
      (filePath == null ||
          FileSystemEntity.typeSync(filePath, followLinks: false) !=
              FileSystemEntityType.file ||
          !filePath.endsWith('.tar.gz'))) {
    throw ArgumentError('A local .tar.gz fixture is required.');
  }
  if (cleanupOnly && (filePath != null || keep)) {
    throw ArgumentError('--cleanup-only takes only --package.');
  }
  if (keep && expect != 'accept') {
    throw ArgumentError('--keep is only valid with --expect=accept.');
  }
  if (!package.startsWith('onepub_staging_test_') ||
      !RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(package)) {
    throw ArgumentError('Use a disposable onepub_staging_test_ package.');
  }
  if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version)) {
    throw ArgumentError('Use the fixture x.y.z version.');
  }
  final credentials = await OnePubTokenStore().credentials;
  final matches = credentials.where((item) => item.url.host == betaHost);
  if (matches.isEmpty) {
    throw StateError('No beta credential found.');
  }
  final credential = matches.first;
  final token = credential.token ?? dcli.env[credential.env ?? ''];
  final segments =
      credential.url.pathSegments.where((value) => value.isNotEmpty).toList();
  if (token == null ||
      token.isEmpty ||
      segments.length < 2 ||
      segments[0] != 'api' ||
      !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(segments[1])) {
    throw StateError('Beta credential is incomplete.');
  }
  final organisation = segments[1];
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  var created = false;
  var retained = false;
  try {
    final ready = await send(
        client, 'GET', Uri.https(betaHost, '/api/test/whoami'), token);
    print('activation check: ${ready.statusCode}');
    if (ready.statusCode != 200) {
      throw StateError('Beta test endpoints are not enabled.');
    }
    if (cleanupOnly) {
      final deleted = await send(client, 'POST',
          Uri.https(betaHost, '/api/test/package/delete/$package'), token);
      print('cleanup disposable package: ${deleted.statusCode}');
      if (deleted.statusCode != HttpStatus.notFound &&
          (deleted.statusCode < 200 || deleted.statusCode >= 300)) {
        exitCode = 2;
        return;
      }
      // A removed test delete route also returns 404. Independently verify
      // absence through the package API before claiming cleanup succeeded.
      final remaining = await send(
          client,
          'GET',
          Uri.https(betaHost, '/api/$organisation/api/packages/$package'),
          token);
      print('verify disposable package absent: ${remaining.statusCode}');
      if (remaining.statusCode != HttpStatus.notFound) {
        exitCode = 2;
      }
      return;
    }
    final create = await send(
        client,
        'POST',
        Uri.https(
            betaHost, '/api/test/package/create/$package', {'team': team}),
        token);
    print('create disposable package: ${create.statusCode}');
    if (create.statusCode < 200 || create.statusCode >= 300) {
      throw StateError('Could not create the disposable package.');
    }
    created = true;

    final uploadUri = Uri.https(
        betaHost, '/api/$organisation/api/packages/versions/newUpload');
    final boundary =
        'onepub-beta-pentest-${DateTime.now().microsecondsSinceEpoch}';
    final request = await client.postUrl(uploadUri);
    request.followRedirects = false;
    request.headers.set(HttpHeaders.authorizationHeader, token);
    request.headers
        .set(HttpHeaders.userAgentHeader, 'OnePub-beta-authorized-pentest/1.0');
    request.headers.contentType =
        ContentType.parse('multipart/form-data; boundary=$boundary');
    final multipartHeader =
        '--$boundary\r\nContent-Disposition: form-data; name="file"; '
        'filename="fixture.tar.gz"\r\nContent-Type: application/octet-stream\r\n\r\n';
    final archiveBytes = await File(filePath!).readAsBytes();
    request
      ..add(multipartHeader.codeUnits)
      ..add(archiveBytes)
      ..add('\r\n--$boundary--\r\n'.codeUnits);
    final uploaded =
        await request.close().timeout(Duration(seconds: completionTimeout));
    final uploadStatus = uploaded.statusCode;
    final location = uploaded.headers.value(HttpHeaders.locationHeader);
    print('archive upload: $uploadStatus; completion URL=${location != null}');
    await uploaded.drain<void>();
    int? finalStatus;
    if (uploadStatus == 204 && location == null) {
      throw StateError('Upload returned 204 without a completion URL.');
    }
    if (location != null && uploadStatus >= 200 && uploadStatus < 300) {
      final completion = uploadUri.resolve(location);
      if (completion.scheme != 'https' || completion.host != betaHost) {
        throw StateError('Completion URL left beta; refusing to follow it.');
      }
      final completed = await send(client, 'GET', completion, token,
          timeout: Duration(seconds: completionTimeout));
      finalStatus = completed.statusCode;
      print('archive completion: $finalStatus');
    }
    final accepted = uploadStatus == 204 &&
        finalStatus != null &&
        finalStatus >= 200 &&
        finalStatus < 300;
    final rejected = uploadStatus == 400 ||
        uploadStatus == 413 ||
        finalStatus == 400 ||
        finalStatus == 413;
    print('fixture accepted=$accepted rejected=$rejected; expected=$expect');
    if (accepted) {
      final identical = await verifyPublishedArchive(
          client, organisation, package, version, token, archiveBytes);
      print('published archive identical to fixture=$identical');
      if (!identical) {
        exitCode = 2;
      }
    }
    if ((expect == 'reject' && !rejected) ||
        (expect == 'accept' && !accepted)) {
      exitCode = 2;
    }
    retained = keep && accepted;
  } finally {
    try {
      if (created && !retained) {
        final deleted = await send(client, 'POST',
            Uri.https(betaHost, '/api/test/package/delete/$package'), token);
        print('cleanup disposable package: ${deleted.statusCode}');
        if (deleted.statusCode < 200 || deleted.statusCode >= 300) {
          exitCode = 2;
        }
      }
      if (retained) {
        print('inspection package retained: $package; run --cleanup-only '
            '--package=$package after inspection');
      }
    } finally {
      client.close(force: true);
    }
  }
}

Future<bool> verifyPublishedArchive(HttpClient client, String organisation,
    String package, String version, String token, List<int> expected) async {
  final archiveUri = Uri.https(betaHost,
      '/api/$organisation/api/packages/$package/versions/$version.tar.gz');
  final redirect = await send(client, 'GET', archiveUri, token);
  if (redirect.statusCode != HttpStatus.temporaryRedirect) {
    throw StateError('Published archive did not issue a download grant.');
  }
  final location = redirect.headers.value(HttpHeaders.locationHeader);
  if (location == null) {
    throw StateError('Published archive grant has no Location.');
  }
  final grant = archiveUri.resolve(location);
  if (grant.scheme != 'https' ||
      grant.host != betaHost ||
      !grant.path.startsWith('/api_download/private/')) {
    throw StateError('Archive grant left beta or was not private.');
  }
  final request =
      await client.getUrl(grant).timeout(const Duration(seconds: 10));
  request.followRedirects = false;
  request.headers
      .set(HttpHeaders.userAgentHeader, 'OnePub-beta-authorized-pentest/1.0');
  final response = await request.close().timeout(const Duration(seconds: 30));
  if (response.statusCode != HttpStatus.ok) {
    await response.drain<void>();
    throw StateError('Published archive grant was not downloadable.');
  }
  var index = 0;
  var identical = true;
  await for (final chunk in response.timeout(const Duration(seconds: 30))) {
    for (final byte in chunk) {
      if (index >= expected.length || byte != expected[index]) {
        identical = false;
      }
      index++;
    }
    if (index > expected.length) {
      break;
    }
  }
  return identical && index == expected.length;
}

Future<HttpClientResponse> send(
    HttpClient client, String method, Uri uri, String token,
    {Duration timeout = const Duration(seconds: 30)}) async {
  if (uri.scheme != 'https' || uri.host != betaHost) {
    throw StateError('Target guard failed: $uri');
  }
  final request =
      await client.openUrl(method, uri).timeout(const Duration(seconds: 10));
  request.followRedirects = false;
  request.headers.set(HttpHeaders.authorizationHeader, token);
  request.headers
      .set(HttpHeaders.userAgentHeader, 'OnePub-beta-authorized-pentest/1.0');
  final response = await request.close().timeout(timeout);
  await response.drain<void>().timeout(timeout);
  return response;
}
