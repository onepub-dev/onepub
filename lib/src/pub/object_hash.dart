import 'package:equatable/equatable.dart';

extension ObjectHash on Object {
  int hash3(String? one, String? two, String? three) {
    return Hasher(one, two, three).hashCode;
  }
}

class Hasher with EquatableMixin {
  Object? one = '';
  Object? two = '';
  Object? three = '';

  Hasher(this.one, this.two, this.three);
  static int hash(Object? one, [Object? two, Object? three]) {
    return new Hasher(one, two, three).hashCode;
  }

  @override
  List<Object?> get props {
    return [one, two, three];
  }
}
