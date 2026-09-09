import 'dart:io';

enum CiProvider {
  githubActions('github', 'github_actions', 'GitHub Actions'),
  gitlabCi('gitlab', 'gitlab_ci', 'GitLab CI/CD'),
  azurePipelines('azure', 'azure_pipelines', 'Azure DevOps Pipelines'),
  bitbucketPipelines('bitbucket', 'bitbucket', 'Bitbucket Pipelines'),
  circleCi('circleci', 'circleci', 'CircleCI'),
  buildkite('buildkite', 'buildkite', 'Buildkite'),
  jenkins('jenkins', 'jenkins', 'Jenkins'),
  teamCity('teamcity', 'teamcity', 'TeamCity'),
  harness('harness', 'harness', 'Harness'),
  travisCi('travis', 'travis_ci', 'Travis CI'),
  googleCloudBuild(
    'google-cloud-build',
    'google_cloud_build',
    'Google Cloud Build',
  ),
  awsCodeBuild('aws-codebuild', 'aws_codebuild', 'AWS CodeBuild');

  const CiProvider(this.id, this.telemetryId, this.displayName);

  final String id;
  final String telemetryId;
  final String displayName;

  static CiProvider parse(String value) => values.firstWhere(
        (provider) => provider.id == value,
        orElse: () => throw FormatException('Unknown CI provider: $value'),
      );
}

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
