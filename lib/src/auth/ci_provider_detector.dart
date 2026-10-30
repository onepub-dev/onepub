import 'dart:io';
import 'ci_provider.dart';

class CiProviderDetector {
  CiProviderDetector({Map<String, String>? environment})
      : environment = environment ?? Platform.environment;

  final Map<String, String> environment;

  List<CiProvider> detect() => [
        if (_set('GITHUB_ACTIONS')) CiProvider.githubActions,
        if (_set('GITLAB_CI')) CiProvider.gitlabCi,
        if (_set('TF_BUILD')) CiProvider.azurePipelines,
        if (_set('BITBUCKET_BUILD_NUMBER')) CiProvider.bitbucketPipelines,
        if (_set('CIRCLECI')) CiProvider.circleCi,
        if (_set('BUILDKITE')) CiProvider.buildkite,
        if (_set('JENKINS_URL')) CiProvider.jenkins,
        if (_set('TEAMCITY_VERSION')) CiProvider.teamCity,
        if (_set('HARNESS_BUILD_ID') || _set('HARNESS_ACCOUNT_ID'))
          CiProvider.harness,
        if (_set('TRAVIS')) CiProvider.travisCi,
        if (_set('BUILD_ID') && _set('PROJECT_ID')) CiProvider.googleCloudBuild,
        if (_set('CODEBUILD_BUILD_ID')) CiProvider.awsCodeBuild,
      ];

  bool get isCi => detect().isNotEmpty || _set('CI');

  String? telemetryProvider() {
    final providers = detect();
    if (providers.length == 1) {
      return providers.single.telemetryId;
    }
    if (providers.length > 1) {
      return 'multiple';
    }
    return _set('CI') ? 'ci' : null;
  }

  CiProvider requireSingle({CiProvider? override}) {
    if (override != null) {
      return override;
    }
    final providers = detect();
    if (providers.isEmpty) {
      throw const FormatException(
          'Unable to detect a supported CI provider. Pass '
          '--provider or provide a JWT using --token-env, --token-stdin, '
          'or --token-file.');
    }
    if (providers.length > 1) {
      throw FormatException('Multiple CI providers were detected: '
          '${providers.map((provider) => provider.id).join(', ')}. '
          'Select one with --provider.');
    }
    return providers.single;
  }

  bool _set(String name) => environment[name]?.isNotEmpty ?? false;
}
