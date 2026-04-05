# AGENTS

OnePub integration and staging tests must never run against production `https://onepub.dev`.

Allowed targets for test execution are:
- local development environments such as `localhost`, loopback, or private-network hosts
- approved non-production OnePub hosts such as `beta.onepub.dev`, `staging.onepub.dev`, and other explicitly sanctioned staging hosts already encoded in the test helpers

When adding or modifying tests:
- route URL selection through the shared safety helpers in `test/test_settings.dart`
- fail fast if the resolved host is not a local/dev or approved staging target
- do not bypass those guards in temporary settings, impersonation helpers, or staging harness code
