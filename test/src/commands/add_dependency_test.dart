import 'package:dcli/dcli.dart';
import 'package:onepub/src/entry_point.dart';
import 'package:test/test.dart';

void main() {
  test('add_dependency ...', () async {
    Settings().setVerbose(enabled: true);
    entrypoint(['add', 'node_mgmt_lib', '^0.3.3']);
  });
}
