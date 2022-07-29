#! /usr/bin/env dcli

import 'dart:io';

import 'package:dcli/dcli.dart';
import 'package:onepub/src/api/api.dart';
import 'package:onepub/src/onepub_settings.dart';
import 'package:onepub/src/util/one_pub_token_store.dart';

import '../../../test/src/test_settings.dart';

/// Called by Critical Test when running unit tests
///
/// We ask the user to login using oauth as we can't di
/// it without user interaction.
///
void main(List<String> args) {
  final pathToBin = DartProject.self.pathToBinDir;

  final pathToOnePubExe = join(pathToBin, 'onepub.dart');

  withTestSettings((testSettings) {
    final user = testSettings.member;

    print('Please login with the $user account');

    /// prompt the user to login into onepub.
    '$pathToOnePubExe login'.run;
    // we need to force a reload of OnePubSettings
    // as the login will have updated it.
    withSettings(() async {
      final tokenStore = OnePubTokenStore();
      if (!tokenStore.isLoggedIn) {
        printerr(red('Login Failed. Tests run stopped'));
        exit(1);
      }


      final onepubSettings = OnePubSettings.use;
      final url = onepubSettings.onepubHostedUrl();
      final credentials = tokenStore.tokenStore.findCredential(url);

      if (credentials == null) {
        printerr(red('Unable to find the OnePub token for $url'));
        exit(1);
      }

    
      final onePubToken = credentials.token;

      testSettings
        ..onepubToken = onePubToken!
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
