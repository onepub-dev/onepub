import 'package:test/test.dart';
import 'fixture_roles.dart';

void main() {
  test('administrator-only fixture upgrades roles without recreating users',
      () async {
    final roles = FixtureRoles<String, int>();
    var created = 0;
    Future<int> create(String _) async => ++created;
    await roles.ensure(['admin'], create);
    expect(created, 1);
    expect(roles.get('admin'), 1);
    await roles.ensure(['admin', 'leader', 'member'], create);
    expect(created, 3);
    expect(roles.get('admin'), 1);
    expect(roles.get('leader'), 2);
    expect(roles.get('member'), 3);
    await roles.ensure(['admin', 'leader', 'member'], create);
    expect(created, 3);
  });
}
