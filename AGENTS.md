# AGENTS

## Release build scope and tooling

- `op-build` and its pre-build/post-build gates may run only work needed to
  produce release artifacts or directly validate their behavior, compatibility,
  security, or installation. Each added gate must identify the artifact or
  product behavior it validates.
- Do not include self-tests of research, migration, benchmark, campaign, or
  developer utilities in the release build merely because they live in the
  repository. Keep useful tooling self-tests in a separate, explicitly invoked
  developer/CI workflow. Tests that exercise shipped behavior remain required.
- Review temporary tooling when its task ends. Delete obsolete tooling together
  with its tests and callers; preserve useful product regression coverage before
  removing or replacing a harness. Do not retain a tool solely because another
  temporary wrapper still references it.
- Write build/test drivers in Dart or Java. Dart scripts must use DCli, start
  with `#! /usr/bin/env dcli`, be executable, and run directly. Do not add Python
  drivers or embedded Python; convert retained Python tooling to Dart or Java.
- Use explicit release-suite selection so new tooling tests cannot silently
  enter the release gate through broad discovery. Keep coverage of shipped
  behavior and accurate execution evidence when changing suite selection.

OnePub integration and staging tests must never run against production `https://onepub.dev`.

Allowed targets for test execution are:
- local development environments such as `localhost`, loopback, or private-network hosts
- approved non-production OnePub hosts such as `beta.onepub.dev`, `staging.onepub.dev`, and other explicitly sanctioned staging hosts already encoded in the test helpers

When adding or modifying tests:
- route URL selection through the shared safety helpers in `test/test_settings.dart`
- fail fast if the resolved host is not a local/dev or approved staging target
- do not bypass those guards in temporary settings, impersonation helpers, or staging harness code
