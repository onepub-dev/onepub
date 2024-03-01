import 'dart:io';

Future<String> readFileAsString(String filePath) async {
  // Open the file
  final file = File(filePath);

  // Read the contents of the file
  final lines = await file.readAsLines();

  // Join the lines into a single string with newlines
  return lines.join('\n');
}
