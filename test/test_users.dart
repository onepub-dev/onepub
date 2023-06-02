import 'package:onepub/src/api/api.dart';
import 'package:onepub/src/api/member.dart';
import 'package:onepub/src/exceptions.dart';
import 'package:onepub/src/util/role_enum.dart';

class TestUsers {
  factory TestUsers({bool init = false}) {
    if (!init && !initialised) {
      throw NotInitialisedException('call TestUsers.init() first');
    }

    return _self;
  }

  TestUsers._internal();

  static final TestUsers _self = TestUsers._internal();

  static bool initialised = false;
  late final Member administrator;
  late final Member teamLeader;
  late final Member basicMember;

  /// creates and caches a set of users with different roles.
  Future<void> init() async {
    if (!initialised) {
      initialised = true;
      administrator = await createAdministrator('admin@testdomain.com');
      teamLeader = await createTeamLeader('teamleader@testdomain.com');
      basicMember = await createBasicMember('basicmember@testdomain.com');
      // cicdMember = await createCICD('cicd@testdomain.com');
    }
  }

  Future<Member> createAdministrator(String emailAddress) => _fetchOrCreate(
      emailAddress: emailAddress,
      firstname: 'One',
      lastname: 'Administrator',
      role: RoleEnum.Administrator);

  Future<Member> createTeamLeader(String emailAddress) async => _fetchOrCreate(
      emailAddress: emailAddress,
      firstname: 'One',
      lastname: 'TeamLeader',
      role: RoleEnum.TeamLeader);

  Future<Member> createBasicMember(String emailAddress) async => _fetchOrCreate(
      emailAddress: emailAddress,
      firstname: 'One',
      lastname: 'Member',
      role: RoleEnum.Collaborator);

  //   Future<Member> createCICDMember(String emailAddress) async
  //    => _fetchOrCreate(
  // emailAddress: emailAddress,
  // firstname: 'One',
  // lastname: 'Member',
  // role: RoleEnum.);

  Future<Member> _fetchOrCreate(
      {required String emailAddress,
      required String firstname,
      required String lastname,
      required RoleEnum role}) async {
    final tokenResponse = await API().exportMemberToken(emailAddress);
    if (tokenResponse.success) {
      // member already exists.
      final memberResponse = await API().fetchMember(tokenResponse.token!);
      if (memberResponse.success) {
        return memberResponse.toMember();
      } else {
        throw APIException(memberResponse.errorMessage);
      }
    } else {
      // create new member
      final createResponse = await API().createMember(
        userEmail: emailAddress,
        firstname: firstname,
        lastname: lastname,
        role: role,
      );

      if (createResponse.success) {
        final onepubToken = await API().exportMemberToken(emailAddress);
        if (!onepubToken.success) {
          throw APIException(
              'Unable to fetch the OnePubToken for $emailAddress ');
        }
        return Member(
            email: emailAddress,
            firstname: firstname,
            lastname: lastname,
            roles: {role},
            organisationName: createResponse.organisationName,
            obfuscatedOrganisationId: createResponse.obfuscateOrganisationId,
            onepubToken: onepubToken.token!);
      }

      throw APIException(createResponse.errorMessage!);
    }
  }
}
