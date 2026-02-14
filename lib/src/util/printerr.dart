import 'dart:async';
import 'dart:io';

/// This is a bit of a hack as we have copied these from dcli_core to avoid
/// a dependency on the whole package. We only need
/// callback used when overloading [printerr] in a DCliZone.
typedef CaptureZonePrintErr = void Function(String);

/// This class is highly experimental - use at your own risk.
/// It is designed to capture any output to print or printerr
/// within the scope of the callback.
/// Key to the overloading [printerr] function.

/// Key to the overloading [printerr] function.
const capturePrinterrKey = 'printerr';

/// [printerr] provides the equivalent functionality to the
/// standard Dart print function but instead writes
/// the output to stderr rather than stdout.
///
/// CLI applications should, by convention, write error messages
/// out to stderr and expected output to stdout.
///
/// [line] the line to write to stderr.
void printerr(Object? object) {
  final line = '$object';

  /// Co-operate with runDCliZone
  final overloaded = Zone.current[capturePrinterrKey] as CaptureZonePrintErr?;
  if (overloaded != null) {
    overloaded(line);
  } else {
    stderr.writeln(line);
  }
}
