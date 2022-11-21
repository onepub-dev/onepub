import '../util/role_enum.dart';

class Member {
  Member({
    required this.email,
    required this.firstname,
    required this.lastname,
    required this.roles,
    required this.onepubToken,
    required this.organisationName,
    required this.obfuscatedOrganisationId,
  });

  String email;
  String firstname;
  String lastname;
  Set<RoleEnum> roles;
  String organisationName;
  String obfuscatedOrganisationId;
  String onepubToken;
}
