import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

/// Recoverable replacement of the credential, account and routing files.
/// Callers supply fixed destinations; the journal never supplies file paths.
class LoginFileTransaction {
  static final Set<String> _activeLocks = {};
  final File journal;
  final Map<String, File> destinations;

  LoginFileTransaction(this.journal, Map<String, File> destinations)
      : destinations = Map.unmodifiable(destinations);

  /// Serializes cooperating writers and restores an interrupted prior write.
  Future<T> locked<T>(Future<T> Function() action) async {
    final lockPath = File('${journal.path}.lock').absolute.path;
    if (!_activeLocks.add(lockPath)) {
      throw StateError('Another login update is already running.');
    }
    try {
      return await _locked(action);
    } finally {
      _activeLocks.remove(lockPath);
    }
  }

  Future<T> _locked<T>(Future<T> Function() action) async {
    await journal.parent.create(recursive: true);
    final lock = await File('${journal.path}.lock').open(mode: FileMode.append);
    try {
      await lock.lock();
      await _recover();
      return await action();
    } finally {
      await lock.close();
    }
  }

  /// Run while [locked]. A failed commit restores all previous files.
  Future<void> commit(Map<String, String> contents,
      {Future<void> Function(int count)? afterReplacement}) async {
    if (contents.length != destinations.length ||
        !contents.keys.every(destinations.containsKey)) {
      throw ArgumentError('Every login file must be included.');
    }
    if (journal.existsSync()) {
      throw StateError('Recover the previous login update first.');
    }
    final previous = <String, String?>{};
    for (final entry in destinations.entries) {
      previous[entry.key] = entry.value.existsSync()
          ? base64Encode(await entry.value.readAsBytes())
          : null;
    }
    await _replace(
        journal,
        utf8.encode(jsonEncode({
          'version': 1,
          'destinations': destinations
              .map((key, file) => MapEntry(key, file.absolute.path)),
          'previous': previous,
        })));
    try {
      var count = 0;
      for (final entry in destinations.entries) {
        await _replace(entry.value, utf8.encode(contents[entry.key]!));
        count++;
        await afterReplacement?.call(count);
      }
      // Deleting the durable rollback record commits the complete update.
      await journal.delete();
    } catch (_) {
      await _recover();
      rethrow;
    }
  }

  Future<void> _recover() async {
    if (!journal.existsSync()) {
      return;
    }
    final Object? decoded = jsonDecode(await journal.readAsString());
    if (decoded is! Map<String, dynamic> || decoded['version'] != 1) {
      throw const FormatException('Invalid login recovery record.');
    }
    final Object? previous = decoded['previous'];
    final Object? recordedDestinations = decoded['destinations'];
    if (recordedDestinations is! Map<String, dynamic> ||
        recordedDestinations.length != destinations.length ||
        !destinations.entries.every((entry) =>
            recordedDestinations[entry.key] == entry.value.absolute.path)) {
      throw const FormatException(
          'Resume login with the original OnePub configuration to recover it.');
    }
    if (previous is! Map<String, dynamic> ||
        previous.length != destinations.length ||
        !previous.keys.every(destinations.containsKey)) {
      throw const FormatException('Invalid login recovery destinations.');
    }
    // Validate the entire record before changing any file.
    final restored = <String, List<int>?>{};
    for (final entry in previous.entries) {
      final Object? value = entry.value;
      if (value != null && value is! String) {
        throw const FormatException('Invalid login recovery contents.');
      }
      restored[entry.key] =
          value == null ? null : base64Decode(value as String);
    }
    for (final entry in destinations.entries) {
      final bytes = restored[entry.key];
      if (bytes != null) {
        await _replace(entry.value, bytes);
      } else if (entry.value.existsSync()) {
        await entry.value.delete();
      }
    }
    await journal.delete();
  }

  static Future<void> _replace(File destination, List<int> contents) async {
    await destination.parent.create(recursive: true);
    final temporary = File('${destination.path}.${const Uuid().v4()}.tmp');
    try {
      await temporary.create(exclusive: true);
      // Restrict access before writing any credential bytes. Windows inherits
      // the user's configuration-directory ACL.
      if (!Platform.isWindows) {
        final result = await Process.run('chmod', ['600', temporary.path]);
        if (result.exitCode != 0) {
          throw const FileSystemException('Cannot protect login files.');
        }
      }
      await temporary.writeAsBytes(contents, flush: true);
      await temporary.rename(destination.path);
    } finally {
      if (temporary.existsSync()) {
        await temporary.delete();
      }
    }
  }
}
