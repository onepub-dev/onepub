#! /usr/bin/env dcli

import 'dart:io';

import 'package:dcli/dcli.dart';
import 'package:onepub/src/api/api.dart';
import 'package:onepub/src/onepub_settings.dart';
import 'package:onepub/src/util/one_pub_token_store.dart';

import '../../../test/src/test_settings.dart';

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
///
void main(List<String> args) {
  final pathToBin = DartProject.self.pathToBinDir;

  final pathToOnePubExe = join(pathToBin, 'onepub.dart');

  withTestSettings((testSettings) {
    final operatorEmail = testSettings.member;
    // final operatorEmail = OnePubSettings.use.operatorEmail;

    // final loginRequired =
    //     !OnePubTokenStore().isLoggedIn || operatorEmail != user;

    // if (loginRequired) {
    print('''

${magenta('Please login with the $operatorEmail account')}
''');

    /// prompt the user to login into onepub.
    '$pathToOnePubExe login'.run;
    // }
    // we need to force a reload of OnePubSettings
    // as the login will have updated it.
    withSettings(() async {
      final tokenStore = OnePubTokenStore();
      if (!tokenStore.isLoggedIn) {
        printerr(red('Login Failed. Tests run stopped'));
        exit(1);
      }
      final onepubSettings = OnePubSettings.use;

      if (onepubSettings.operatorEmail != operatorEmail) {
        printerr(red('You logged in with the wrong email address. '
            'Use $operatorEmail and try again.'));
        exit(1);
      }

      final url = onepubSettings.onepubHostedUrl();
      final credentials = tokenStore.tokenStore.findCredential(url);

      if (credentials == null) {
        printerr(red('Unable to find the OnePub token for $url'));
        exit(1);
      }

      // store the authed token into the testing setting file
      // for use by unit tests.
      final onePubToken = credentials.token;

      testSettings
        ..onepubToken = onePubToken!
        ..organisationId = onepubSettings.obfuscatedOrganisationId
        ..organisationName = onepubSettings.organisationName
        ..onepubUrl = onepubSettings.onepubUrl!
        ..save();

      final result =
          await API().createMember('bsutton@onepub.dev', 'Test', 'User');
      if (!result.success) {
        // we don't care if the member already exits
        if (result.errorMessage != 'Member exists') {
          printerr(red('Failed to create member: ${result.errorMessage}'));
          exit(1);
        }
      }
    });
  }, forAuthentication: true);
}
