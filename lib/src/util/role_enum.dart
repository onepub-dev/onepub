import '../exceptions.dart';

/// this class members must align with the java
/// RoleEnum class.
/// Note: these member names are case sensitive
/// so don't change them!!!
// ignore_for_file: constant_identifier_names

enum RoleEnum {
  SystemAdministrator,
  Administrator,
  Uploader,
  TeamLeader,
  Member,
  PackageLicensee,
  DartDocumenter
}

extension RoleEnumHelper on RoleEnum {
  String get name => toString().split('.').last;

  static RoleEnum byName(String role) {
    for (final value in RoleEnum.values) {
      if (role == value.name) {
        return value;
      }
    }
    throw InvalidRoleNameException('The role name $role does not exist');
  }
}

class InvalidRoleNameException extends OnePubCliException {
  InvalidRoleNameException(String message) : super(message);
}
