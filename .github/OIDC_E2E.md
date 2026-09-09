# GitHub trusted publishing E2E build gate

A regular Vaadin `op-build` now waits for a real GitHub identity test before
publishing its Docker image or packaging the release. The test uses the exact
unpublished image built locally and a pushed, immutable CLI commit.

## How GitHub reaches the test server

Register a **self-hosted Linux GitHub Actions runner on the build machine**.
Give it a unique label, for example `onepub-build-brett`. Do not use the same
label on another machine. The workflow runs directly on that host, so its
`127.0.0.1` is the same loopback interface as the temporary Docker stack.
No public tunnel, staging deployment or inbound firewall opening is needed.
The runner needs outbound HTTPS access to GitHub and Dart package dependencies.

If op-build itself runs inside Actions, use a second idle runner on the same
machine for the E2E job. A runner cannot execute a second job while its first
job waits for it. Preflight rejects a busy runner.

## One-time setup

1. Commit and push the candidate CLI, including this workflow and its Dart
   helpers. The workflow must also exist on the repository's default branch
   for `workflow_dispatch` to be available. Configure `--trusted-workflow-ref`
   to the branch containing this workflow when testing another candidate.
2. Register the dedicated runner in `onepub-dev/onepub` and keep it online.
   It must be permitted to execute workflows in this repository.
3. Create the GitHub Environment `oidc-e2e`. Restrict it to the release/workflow
   branches you trust. No OnePub token, endpoint or audience secret is needed.
   Any environment approval must complete within the build's 30-minute deadline.
4. Authenticate `gh` on the build machine with repository access and Actions
   write permission for dispatch, polling and cancellation. Preflight also
   reads repository metadata, environments and self-hosted runner availability;
   the authenticated account needs access to those endpoints.

Do not attach this runner/environment to untrusted pull-request workflows.
Only the manually dispatched release workflow requests `id-token: write`.

## Run

From the sibling `onepub-deploy` repository:

```sh
dart run bin/op-build.dart --trusted-runner-label onepub-build-brett
```

To test an existing **local** candidate image without building or deploying:

```sh
dart run bin/op-build.dart --no-build --no-deploy --version 5.17.2 --system-test-suite integration --trusted-runner-label onepub-build-brett
```

The image must exist locally or in the registry. `--no-build` does not create it.
The default workflow ref is `main`; override it with `--trusted-workflow-ref`.
The default runner label is `onepub-build`. For an explicitly local-only run,
`--no-trusted-publishing-test` skips this gate. Skipping post-build tests or
using a quick build also skips it and is not evidence of a real GitHub E2E pass.

## What the build verifies

1. Fail early if the CLI source is dirty/unpushed, the workflow/environment is
   missing, or exactly one matching idle runner is not online.
2. Run the normal local CLI suites, then create a fresh isolated MariaDB/Vaadin
   stack for trusted publishing using the same candidate image.
3. Create a disposable test package and a package-scoped GitHub issuer/trust
   rule. Pin repository owner ID, repository ID, workflow ref, workflow SHA,
   environment, and a per-build audience. Bootstrap credentials stay local.
4. Dispatch the workflow with the exact CLI SHA and generated test details.
   Follow the run ID returned by GitHub, with a unique run title as a second
   check. Never select the latest run or reuse an earlier successful result.
5. On the self-hosted runner, check out that CLI SHA, verify the server version,
   and run `onepub login trusted --publish-only` with a real GitHub JWT. Publish
   version 1.0.0 of the disposable package using the installed restricted token.
6. After GitHub reports success, verify package metadata, a nonempty downloadable
   archive and a `TOKEN_EXCHANGED` audit record locally. These checks use the
   isolated bootstrap credential because package-scoped tokens cannot download.
7. Remove temporary credentials on the runner and the entire test stack on the
   build machine. Failures, cancellations, skips, API errors or timeouts fail the
   build. On a wait failure the build requests cancellation of that exact run.

All OnePub HTTP targets are checked through `test/test_settings.dart`. The
workflow and bootstrap additionally require the allocated `127.0.0.1` target.
Nothing contacts production `onepub.dev`.

GitHub dispatch/polling uses the REST API through `gh`, with API version
`2026-03-10`, whose dispatch response includes the workflow run ID:
https://docs.github.com/en/rest/actions/workflows#create-a-workflow-dispatch-event
