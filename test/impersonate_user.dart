import 'package:dcli/dcli.dart';
import 'package:dcli_core/dcli_core.dart' as core;
import 'package:onepub/src/api/api.dart';
import 'package:onepub/src/api/member.dart';
import 'package:onepub/src/exceptions.dart';
import 'package:onepub/src/onepub_settings.dart';
import 'package:onepub/src/util/one_pub_token_store.dart';
import 'package:onepub/src/util/role_enum.dart';

import 'test_settings.dart';

/// to call this the host system must be logged into OnePub with
/// a system admin account.
Future<void> impersonateMemberByEmail({
  required String userEmailAddress,
  required Future<void> Function() action,
}) async {
  var onepubTokenResponse = await API().exportMemberToken(userEmailAddress);
  if (!onepubTokenResponse.success) {
    // member doesn't exists so lets create them.
    await API().createMember(
        userEmail: userEmailAddress,
        firstname: 'Test',
        lastname: 'User',
        role: RoleEnum.Member);
    onepubTokenResponse = await API().exportMemberToken(userEmailAddress);
  }

  if (!onepubTokenResponse.success) {
    throw OnePubCliException(
        'Unable to fetch user: ${onepubTokenResponse.errorMessage}');
  }
  final onepubToken = onepubTokenResponse.token!;

  final response = await API().fetchMember(onepubToken);

  await impersonateMember(member: response.toMember(), action: action);
}

/// to call this the host system must be logged into OnePub with
/// a system admin account.
Future<void> impersonateMember({
  required Member member,
  required Future<void> Function() action,
}) async {
  await core.withTempDir((tempSettingsDir) async {
    // control the location of the onepub settings file.
    // Create our own version of the OnePubSettings file.
    await OnePubSettings.withPathTo<void>(tempSettingsDir, () async {
      // final testSettings = TestSettings();
      // final settings = OnePubSettings.use()
      //   ..operatorEmail = testSettings.member
      //   ..organisationName = testSettings.organisationName
      //   ..obfuscatedOrganisationId = testSettings.organisationId
      //   ..onepubUrl = testSettings.onepubUrl
      //   ..save();

      final testSettings = TestSettings();
      final settings = OnePubSettings.use()
        ..operatorEmail = member.email
        ..onepubUrl = testSettings.onepubUrl
        ..organisationName = member.organisationName
        ..obfuscatedOrganisationId = member.obfuscatedOrganisationId;
      await settings.save();

      // set an alternate location for the token store
      await OnePubTokenStore.withPathTo(tempSettingsDir, () async {
        OnePubTokenStore().addToken(
            onepubApiUrl: settings.onepubApiUrlAsString,
            onepubToken: member.onepubToken);

        await action();
      });
    });
  });
}

/// Creates a safe testing area using the currently logged in users
/// details.
Future<void> withTestZone({
  required String userEmailAddress,
  required Future<void> Function() action,
}) async {
  var onepubTokenResponse = await API().exportMemberToken(userEmailAddress);
  if (!onepubTokenResponse.success) {
    await API().createMember(
        userEmail: userEmailAddress,
        firstname: 'Test',
        lastname: 'User',
        role: RoleEnum.Member);
    onepubTokenResponse = await API().exportMemberToken(userEmailAddress);
  }

  if (!onepubTokenResponse.success) {
    throw OnePubCliException(
        'Unable to fetch user: ${onepubTokenResponse.errorMessage}');
  }
  final onepubToken = onepubTokenResponse.token!;

  final response = await API().fetchMember(onepubToken);
  await impersonateMember(member: response.toMember(), action: action);
}

Future<Member> fetchTestUser({required String userEmailAddress}) async {
  final testSettings = TestSettings();

  print('''
  ${magenta('When prompted, provide a temp token from the Member | Organisation Tab')}
  ${testSettings.onepubUrl}
  Note: this token expires in an hour.
  ''');

  final onepubTokenOfTargetMember = ask('Temp Token:', hidden: true);

  final response = await API().fetchMember(onepubTokenOfTargetMember);
  if (!response.success) {
    throw ImpersonationException(
        'Unable to fetch Member: ${response.errorMessage}');
  }

  return response.toMember();
}

class ImpersonationException implements Exception {
  ImpersonationException(this.message);
  String message;
}
