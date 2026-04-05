import 'dart:async';
import 'dart:io';

import 'package:onepub/src/util/send_command.dart';

Future<void> cleanupPackage(String packageName) async {
  stdout.writeln('Cleaning up package $packageName...');
  const maxAttempts = 3;
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    EndpointResponse response;
    try {
      response = await sendCommand(
        command: 'test/package/delete/$packageName',
        commandType: CommandType.cli,
        method: Method.post,
      );
    } on HttpException catch (e) {
      if (attempt < maxAttempts) {
        final backoffMs = 400 * attempt;
        stderr.writeln(
            'Cleanup transport warning (attempt $attempt/$maxAttempts): '
            '$e. Retrying in ${backoffMs}ms...');
        await Future<void>.delayed(Duration(milliseconds: backoffMs));
        continue;
      }
      rethrow;
    }

    if (response.success) {
      return;
    }

    // Cleanup is idempotent; if package is already absent we are done.
    if (response.status == HttpStatus.notFound) {
      return;
    }

    final message = response.errorMessage;
    final deletePermissionDenied =
        message.contains('s3:DeleteObject') || message.contains('AccessDenied');
    final transient = response.status >= HttpStatus.internalServerError ||
        message.contains('ticket raised');
    if (deletePermissionDenied) {
      stderr.writeln(
          '''
Cleanup skipped for $packageName: delete permission is not available on this environment.''');
      return;
    }
    if (transient && attempt < maxAttempts) {
      await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
      continue;
    }

    if (message.isNotEmpty) {
      throw StateError('Cleanup failed: $message');
    }
    throw StateError('Cleanup failed without message.');
  }
}
