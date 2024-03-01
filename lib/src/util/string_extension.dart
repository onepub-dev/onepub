import 'package:dcli_core/dcli_core.dart' as core;

import 'file_sync.dart';

extension StringExtension on String {
  /// Treat the contents of 'this' String  as the name of a file
  /// and appends [line] to the file.
  /// If [newline] is null or isn't passed then the platform
  /// end of line characters are appended as defined by
  /// [Platform().eol].
  /// Pass null or an '' to [newline] to not add a line terminator.  ///
  /// e.g.
  /// ```dart
  /// '.bashrc'.append('export FRED=ONE');
  /// ```
  /// Use [withOpenFile] for better performance.
  void append(String line, {String? newline}) {
    newline ??= core.eol;
    withOpenFile(this, (file) {
      file.append(line, newline: newline);
    });
  }

  /// Truncates and Writes [line] to the file terminated by [newline].
  /// If [newline] is null or isn't passed then the platform
  /// end of line characters are appended as defined by
  /// [Platform().eol].
  /// Pass null or an '' to [newline] to not add a line terminator.///
  /// e.g.
  /// ```dart
  /// '/tmp/log'.write('Start of Log')
  /// ```
  ///
  /// Use [withOpenFile] for better performance.
  void write(String line, {String? newline}) {
    newline ??= core.eol;
    withOpenFile(this, (file) {
      file.write(line, newline: newline);
    });
  }
}
