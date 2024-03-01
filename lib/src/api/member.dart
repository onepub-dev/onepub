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
    final onepubApiUrl = OnePubSettings.use().onepubApiUrl;

    final tokenStore = OnePubTokenStore();

    final token = await tokenStore.getToken(onepubApiUrl.toString());
    if (token != null) {
      final member = await API().fetchMember(token);
      return member.roles.contains(RoleEnum.SystemAdministrator.name);
    }

    return false;
  }
}
