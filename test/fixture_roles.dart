/// Provision requested roles, including requests made after initial setup.
class FixtureRoles<K, T> {
  final _values = <K, T>{};

  T get(K role) =>
      _values[role] ??
      (throw StateError('Role $role was not requested during fixture setup.'));
  bool containsAll(Iterable<K> roles) => roles.every(_values.containsKey);
  void set(K role, T value) {
    _values[role] = value;
  }

  Future<void> ensure(Iterable<K> roles, Future<T> Function(K) create) async {
    for (final role in roles) {
      if (!_values.containsKey(role)) {
        _values[role] = await create(role);
      }
    }
  }
}
