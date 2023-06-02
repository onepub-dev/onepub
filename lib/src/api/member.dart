import '../exceptions.dart';
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

  /// Throws [CredentialsException] if we can't obtain
  /// the logged in user.
  static Future<Member> loggedInMember() async {
    final onepubUrl = OnePubSettings.use().onepubApiUrl;

    // if (onepubUrl == null) {
    //   throw CredentialsException(
    //       'Unable to obtain the onepubUrl from the OnePub settings.');
    // }

    final tokenStore = OnePubTokenStore();

    final token = tokenStore.getTokenByUri(onepubUrl);

    if (token == null) {
      throw CredentialsException('No token found for $onepubUrl');
    }

    final response = await API().fetchMember(token);
    if (!response.success) {
      throw CredentialsException(response.errorMessage);
    }
    return response.toMember();
  }

  /// Returns true if the currently logged in and active user is a system
  /// administrator
  static Future<bool> isSystemAdministrator() async {
    final member = await loggedInMember();

    return member.hasRole(RoleEnum.SystemAdministrator);
  }

  bool hasRole(RoleEnum systemAdministrator) =>
      roles.contains(systemAdministrator);
}
