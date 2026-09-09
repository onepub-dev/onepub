import 'package:onepub/src/auth/ci_provider.dart';
import 'package:test/test.dart';

void main() {
  final cases = <CiProvider, Map<String, String>>{
    CiProvider.githubActions: {'GITHUB_ACTIONS': 'true'},
    CiProvider.gitlabCi: {'GITLAB_CI': 'true'},
    CiProvider.azurePipelines: {'TF_BUILD': 'true'},
    CiProvider.bitbucketPipelines: {'BITBUCKET_BUILD_NUMBER': '1'},
    CiProvider.circleCi: {'CIRCLECI': 'true'},
    CiProvider.buildkite: {'BUILDKITE': 'true'},
    CiProvider.jenkins: {'JENKINS_URL': 'https://jenkins.example'},
    CiProvider.teamCity: {'TEAMCITY_VERSION': '2026.03'},
    CiProvider.harness: {'HARNESS_BUILD_ID': 'build'},
    CiProvider.travisCi: {'TRAVIS': 'true'},
    CiProvider.googleCloudBuild: {
      'BUILD_ID': 'build',
      'PROJECT_ID': 'project',
    },
    CiProvider.awsCodeBuild: {'CODEBUILD_BUILD_ID': 'build'},
  };

  for (final entry in cases.entries) {
    test('detects ${entry.key.displayName}', () {
      final detector = CiProviderDetector(environment: entry.value);

      expect(detector.detect(), [entry.key]);
      expect(detector.telemetryProvider(), entry.key.telemetryId);
      expect(detector.isCi, isTrue);
    });
  }

  test('provider override resolves ambiguous nested CI environments', () {
    final detector = CiProviderDetector(environment: {
      'GITHUB_ACTIONS': 'true',
      'CI': 'true',
      'JENKINS_URL': 'https://jenkins.example',
    });

    expect(detector.detect(), hasLength(2));
    expect(
      detector.requireSingle(override: CiProvider.githubActions),
      CiProvider.githubActions,
    );
    expect(detector.telemetryProvider(), 'multiple');
  });

  test('generic CI is reported without guessing a provider', () {
    final detector = CiProviderDetector(environment: {'CI': 'true'});

    expect(detector.detect(), isEmpty);
    expect(detector.isCi, isTrue);
    expect(detector.telemetryProvider(), 'ci');
    expect(detector.requireSingle, throwsFormatException);
  });
}
