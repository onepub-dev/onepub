#!/usr/bin/env dart

import 'dart:io';

import 'package:onepub/src/api/api.dart';
import 'package:onepub/src/api/member.dart';
import 'package:onepub/src/onepub_settings.dart';
import 'package:onepub/src/util/one_pub_token_store.dart';
import 'package:settings_yaml/settings_yaml.dart';

import '../test/test_settings.dart';

Future<void> main(List<String> args) async {
  try {
    final testSettings = TestSettings();

    await withTestServer(() async {
      final settings = OnePubSettings.use();
      final store = OnePubTokenStore();
      final apiUrl = settings.onepubApiUrl.toString();
      final token = await store.getToken(apiUrl);

      if (token == null || token.isEmpty) {
        stderr
          ..writeln(
            'System test preflight failed: no token available for $apiUrl.',
          )
          ..writeln(
            'Place a valid System Administrator test token in '
            '${testSettings.pathToTestSettings} under onepub_token:.',
          );
        exit(2);
      }

      final memberResponse = await API().fetchMember(token);
      if (!memberResponse.success) {
        final serverMessage = memberResponse.errorMessage.trim();
        stderr.writeln(
          'System test preflight failed: unable to resolve the current test '
          'member for $apiUrl.',
        );
        if (serverMessage.isNotEmpty) {
          stderr.writeln('Server response: $serverMessage');
        }
        if (serverMessage.contains('Test endpoints are disabled')) {
          stderr
            ..writeln(
              'Enable test endpoints for ${settings.onepubUrl} before '
              'running system tests.',
            )
            ..writeln(
              'For a local op-build run, add TEST_ENDPOINTS_ENABLED: true to '
              'onepub-deploy/config/settings.yaml and recreate vaadin.',
            )
            ..writeln(
              'For an installed local server, add TEST_ENDPOINTS_ENABLED: true '
              'to /opt/onepub/config/settings.yaml and restart vaadin.',
            )
            ..writeln(
              'If this is already set, check MODE is not production; '
              'production mode also disables test endpoints.',
            )
            ..writeln('Token source: ${_describeTokenSource(testSettings)}');
          exit(2);
        }
        stderr
          ..writeln(
            'Refresh onepub/test/test_settings.yaml so onepub_token: contains '
            'a current System Administrator token for ${settings.onepubUrl}.',
          )
          ..writeln('Token source: ${_describeTokenSource(testSettings)}');
        exit(2);
      }

      final member = memberResponse.toMember();
      final isSystemAdmin = await Member.isSystemAdministrator();
      if (!isSystemAdmin) {
        stderr
          ..writeln(
            'System test preflight: reduced coverage only. '
            'Current test member ${member.email} is not a System '
            'Administrator for ${settings.onepubUrl}.',
          )
          ..writeln(
            'Dedicated Administrator/TeamLeader/Collaborator test users cannot '
            'be provisioned, so role-separation coverage will be reduced.',
          )
          ..writeln(
            'Update onepub/test/test_settings.yaml so onepub_token: contains '
            'a real System Administrator test token, or rerun op-build with '
            '--no-test if you want to skip tests entirely.',
          )
          ..writeln('Token source: ${_describeTokenSource(testSettings)}');
        exit(3);
      }
    }, resolveOrganisationToken: false);
  } on Object catch (e) {
    stderr.writeln('System test preflight failed: $e');
    exit(2);
  }
}

String _describeTokenSource(TestSettings testSettings) {
  final settings =
      SettingsYaml.load(pathToSettings: testSettings.pathToTestSettings);
  final fileToken = settings.asString('onepub_token').trim();
  if (fileToken.isNotEmpty) {
    return '${testSettings.pathToTestSettings}: onepub_token';
  }

  final envToken = Platform.environment['ONEPUB_TOKEN']?.trim() ?? '';
  if (envToken.isNotEmpty) {
    return 'none (environment variable ONEPUB_TOKEN is ignored for system '
        'tests)';
  }

  return 'none';
}
