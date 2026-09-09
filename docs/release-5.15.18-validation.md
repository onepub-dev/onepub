# CLI release validation

Native Maven/Gradle/Swift support is retained on
`support-native-language-projects`, commit `4ee3b09c`. It is excluded from
`release/cli-5.15.18-compatibility`; server 5.15.18 has no native endpoints.

## Automated local checks

```sh
dart analyze lib test/src/api tool/check_release_server.dart
dart test test/src/api test/src/util/send_command_test.dart test/src/onepub_settings_test.dart test/test_settings_test.dart test/src/my_runner_test.dart
```

`release_contract_test.dart` uses synthetic response values matching the Java
response classes in server tag 5.15.18, not responses captured from production.
It covers status, organisation, export, login, logout and package metadata.
`import_audit_test.dart` uses guarded loopback HTTP servers and isolated settings
and token stores. It checks audit payload/headers, credential persistence despite
500/malformed/stalled responses, deadline connection cleanup, split UTF-8 decoding,
and preservation of existing credentials/settings after invalid required responses.

## Isolated Docker integration run

The coordinated server release target is **5.17.2**. From the sibling
`onepub-deploy` checkout, run:

```sh
dart run bin/op-build.dart --no-build --no-deploy --version 5.17.2 --system-test-suite integration
```

The GitHub gate requires the self-hosted runner setup in
[OIDC_E2E.md](../.github/OIDC_E2E.md). Add `--trusted-runner-label` for that
machine. Use `--no-trusted-publishing-test` only for an explicitly local-only run.

This provisions a temporary MariaDB database and Vaadin Docker container,
bootstraps test credentials, runs the CLI suite against an allocated loopback
port, and removes the stack afterward. It uses the existing image for that
version and does not build, publish or deploy a release.

The bootstrap writes the allocated URL and token to `test/test_settings.yaml`.
After container cleanup that URL no longer has a listener; running the CLI test
runner alone does not recreate the container.

## Smoke run against an already running test server

Use **5.17.2** to an approved non-production environment with test endpoints
and the dedicated test users configured. Do not run any tests against onepub.dev.
First verify the version using the same URL that will be passed to the suite:

```sh
dart run tool/check_release_server.dart https://staging.onepub.dev 5.17.2 && dart run tool/run_system_tests.dart --system custom --url https://staging.onepub.dev --suite integration
```

The preflight uses `TestSettings.resolveOnePubUrl` and rejects production before
making a request. It is unauthenticated and does not modify operator settings.
The integration suite includes real CLI login, import, export, logout and package
commands; login requires the existing test login setup. This smoke run requires a
running server and suitable test credentials, unlike the local contract tests.

For audit persistence, the server already has
`src/test/java/dev/onepub/api/ImportTokenRouteTest.java`, including
`importTokenPersistsPayloadAndHeaders`. Run that test with the server's approved
local test database configuration, and verify a CLI import appears in the staging
CLI log with the expected source, CI metadata and initiator. The CLI loopback tests
verify the transmitted request; they do not claim to verify database persistence.
