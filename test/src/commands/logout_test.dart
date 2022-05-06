import 'package:onepub/src/commands/logout.dart';
import 'package:onepub/src/entry_point.dart';
import 'package:test/test.dart';

void main() {
  test('logout ...', () async {
    entrypoint(['logout']);
  });
}
