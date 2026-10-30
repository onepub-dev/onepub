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

  final String id;
  final String telemetryId;
  final String displayName;

  const CiProvider(this.id, this.telemetryId, this.displayName);

  static CiProvider parse(String value) => values.firstWhere(
        (provider) => provider.id == value,
        orElse: () => throw FormatException('Unknown CI provider: $value'),
      );
}
