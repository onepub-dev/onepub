import '../onepub_settings.dart';
import '../util/one_pub_token_store.dart';
import '../util/role_enum.dart';
import 'api.dart';

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

  /// Returns true if the currently logged in and active user is a system
  /// administrator
  static Future<bool> isSystemAdministrator() async {
    final onepubUrl = OnePubSettings.use().onepubUrl!;

    final tokenStore = OnePubTokenStore();

    final token = tokenStore.getToken(onepubUrl);
    if (token != null) {
      final member = await API().fetchMember(token);
      return member.roles.contains('System Administrator');
    }

    return false;
  }
}
