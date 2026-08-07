# GitHub OIDC end-to-end test

The `GitHub OIDC E2E` workflow runs the checked-out OnePub CLI against a real
JWT issued by GitHub Actions. It covers GitHub provider detection, ID-token
acquisition, OnePub token exchange, an authenticated organisation lookup, and
installation of the short-lived token into Dart's hosted-repository token
store. No long-lived OnePub credential is stored in GitHub.

The existing unit and server E2E tests use controlled test JWTs. Keep them:
they cover rejection, replay, revocation, and claim-boundary cases that should
not be tested by repeatedly mutating a shared external environment. This
workflow adds the provider integration that those deterministic tests cannot
exercise.

## One-time setup

1. Deploy the OIDC branch to an isolated, externally reachable HTTPS test
   instance. Never point this workflow at production or beta.
2. In the CLI repository, create a protected GitHub Environment named
   `oidc-e2e`. Restrict its deployment branches to the OIDC branch while the
   feature is under development.
3. Add these environment variables:

   - `ONEPUB_OIDC_E2E_URL`: the test instance base URL.
   - `ONEPUB_OIDC_E2E_AUDIENCE`: a test-specific audience, such as
     `https://staging.onepub.dev/github-oidc-e2e`.

4. On that OnePub instance, create a restricted CI/CD member and a trusted-CI
   issuer profile with:

   - issuer: `https://token.actions.githubusercontent.com`
   - JWKS URI: `https://token.actions.githubusercontent.com/.well-known/jwks`
   - audience: exactly `ONEPUB_OIDC_E2E_AUDIENCE`
   - algorithm: `RS256`

5. Create a trust rule for the CI/CD member. At minimum, constrain the immutable
   `repository_owner_id` and `repository_id` claims to this repository's values,
   and constrain `environment=oidc-e2e`. GitHub exposes the numeric IDs in the
   workflow context as `github.repository_owner_id` and
   `github.event.repository.id`.

The GitHub Environment changes the token subject to the environment form. Its
deployment protection rules are therefore part of the trust boundary. For an
even narrower rule, also constrain `workflow_ref` to this workflow and its
approved branch after inspecting the exact claim from a test run.

## Run it

Push the OIDC branch, open **Actions > GitHub OIDC E2E**, select the OIDC branch,
and choose **Run workflow**. A successful job proves that GitHub signed the
workload JWT, OnePub verified and exchanged it, the issued OnePub token could
read the organisation, and Dart installed it for the returned hosted URL.

The workflow deliberately has no automatic pull-request trigger. GitHub does
not pass protected environment configuration to untrusted fork workflows, and
the external test instance must be running the matching unreleased server
branch before this integration can succeed.
