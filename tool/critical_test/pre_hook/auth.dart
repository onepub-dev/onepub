#! /usr/bin/env dcli

import 'dart:io';

import 'package:dcli/dcli.dart';
import 'package:onepub/src/api/member.dart';
import 'package:onepub/src/onepub_settings.dart';
import 'package:onepub/src/util/one_pub_token_store.dart';

/// Called by Critical Test when running unit tests
///
/// We ask the user to login using oauth as we can't do
/// it without user interaction.
/// The auth process has to use the standard token store as the
/// dart pub publish command can't be given an alternate token store.
///
/// As part of the auth process we need to know what user to tell
/// the user to login to.
/// This is taken from the test_settings.yaml file.
///
/// The onepub login process will update the .onepub/settings.yaml with
/// the logged in user details.
///
/// Ideally we don't want to affect the users normal environment so we should
/// write the details to an alternate settings.yaml.
///
/// Once the user has logged in we need to transfer the credentials to the
/// test_settings.yaml and discard the settings.yaml.
///
/// For subsequent unit tests we get the settings from test_settings and
/// transfer them into a tmp settings.yam.
///
/// All code that runs (including setup) needs to use a temp settings.yaml
/// as it will be the only one to have the correct details.
Future<void> main(List<String> args) async {
  // final pathToBin = DartProject.self.pathToBinDir;

  // final pathToOnePubExe = join(pathToBin, 'onepub.dart');

  await preConditionIsLoggedIn();
}

// await withTestSettings((testSettings) async {

//   // we need to force a reload of OnePubSettings
//   // as the import will have updated it.
//   await OnePubSettings.withPathTo<void>(
//       OnePubSettings.defaultPathToSettingsDir, () async {
//     final tokenStore = OnePubTokenStore();
//     final onepubSettings = OnePubSettings.use();
//     if (!tokenStore.isLoggedIn(onepubSettings.onepubApiUrl)) {
//       printerr(red('Login Failed. Tests run stopped'));
//       exit(1);
//     }

//     await fetchTestUser(testSettings, pathToOnePubExe);

//     final url = onepubSettings.onepubApiUrl;
//     final credentials = tokenStore.tokenStore.findCredential(url);

//     if (credentials == null) {
//       printerr(red('Unable to find the OnePub token for $url'));
//       exit(1);
//     }

//     // store the authed token into the testing setting file
//     // for use by unit tests.
//     final onePubToken = credentials.token;

//     testSettings
//       ..onepubToken = onePubToken!
//       ..organisationId = onepubSettings.obfuscatedOrganisationId
//       ..organisationName = onepubSettings.organisationName
//       ..onepubUrl = onepubSettings.onepubUrl!
//       ..save();
//   });
// });
// void loginIfRequired(String pathToOnePubExe) {
//   final tokenStore = OnePubTokenStore();
//   if (!tokenStore.isLoggedIn(OnePubSettings.use().onepubApiUrl)) {
//     print('''

//   ${magenta('Please login with System Administrator account')}
//   ''');

//     /// prompt the user to login into onepub.
//     'dart $pathToOnePubExe login'.run;
//   }
// }

/// Check that the user is logged in before we proceed.
Future<void> preConditionIsLoggedIn() async {
  final tokenStore = OnePubTokenStore();
  final onepubApiUrl = OnePubSettings.use().onepubApiUrl;
  if (!tokenStore.isLoggedIn(onepubApiUrl)) {
    printerr(red('Please use onepub import to import a '
        'System Administrator from the test db'));
    exit(1);
  }

  final token =
      tokenStore.getToken(onepubApiUrl.toString());
  if (token == null) {
    printerr(red('''
Token store is in an inconsistent state - no credential found for logged in user.
Delete tokens using `dart pub token remove` and then re-auth'''));
    exit(1);
  }

  if (!(await Member.isSystemAdministrator())) {
    printerr(red('The Imported user is not a System Administrator'));
    exit(1);
  }
}
