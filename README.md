# OnePub

OnePub is a hosted (SAAS) private package repository for Dart and Flutter.

> OnePub is to Dart what NPM is to Javascript

OnePub aims to provide the same experience as pub.dev but for your own private packages only shared within your team.

* A private repository for your Dart and Flutter packages.
* Painless IDE and CLI Integration.
* Watch public and private packages and receive update notices.
* Hosted API documentation for your private packages
* Search both pub.dev and your private packages from one search page.
* Secure your supply chain by vendoring*1 each of you dependencies

OnePub lets you use the existing Dart tooling (dart pub publish | flutter pub publish) to publish packages to your own private repository.

OnePub includes a free plan for small teams.

To take it for a spin by registering at:
https://onepub.dev

Full documentation is available at:

https://docs.onepub.dev

# Installing
To install onepub run:

```bash
dart pub global activate onepub
onepub login
```
The `onepub login` command will register you with OnePub.

# Trusted publishing login

```sh
onepub login trusted
```

Log in from CI/CD without storing a OnePub token. Requires trusted publishing
to be configured in OnePub.

The command detects your CI provider automatically. Run
`onepub login trusted --help` for provider and identity-token options.

# Publish
To publish a private package to OnePub

```bash
cd <my first project>
onepub pub private
dart pub publish
```

# Add a private dependency

To add a dependency on a private package to your project

```bash
cd <my second project>
onepub pub add <my first project>
```

# Staging test suite

To run the staging server smoke/load checks (doctor, publish/get, metadata, archive, auth tests, rate-limit burst/recovery):

```bash
dart test test/src/onepub_command/staging
```

Or run a specific load suite:

```bash
dart run tool/run_system_tests.dart --system local --suite download-pub-flow-stress
```

Optional environment overrides:

```bash
ONEPUB_STAGING_URL=https://staging.onepub.dev
ONEPUB_TEAM=MyTeam
ONEPUB_INVALID_TEAM=not-a-team
ONEPUB_RATE_ROUTE=organisation/details
ONEPUB_RATE_REQUESTS=75
ONEPUB_SKIP_PACKAGE_CREATE=true
ONEPUB_SKIP_CLEANUP=true
ONEPUB_SKIP_PUBLISH=true
ONEPUB_SKIP_PUB_GET=true
ONEPUB_SKIP_RATE_LIMIT=true
ONEPUB_SKIP_DOWNLOAD_STRESS=true
ONEPUB_SKIP_RATE_LIMIT_RECOVERY=true
ONEPUB_SKIP_UNAUTHORIZED_TEST=true
ONEPUB_SKIP_INVALID_TOKEN_TEST=true
ONEPUB_SKIP_METADATA_TEST=true
ONEPUB_SKIP_ARCHIVE_TEST=true
ONEPUB_SKIP_TEAM_NEGATIVE=true
ONEPUB_SKIP_TOKEN_INVALIDATION=true
ONEPUB_DOWNLOAD_STRESS_REQUESTS=50
ONEPUB_DOWNLOAD_STRESS_CONCURRENCY=20
ONEPUB_DOWNLOAD_STRESS_PACKAGE_SIZE_MB=0
```


*1 Vendoring is the process of storing your own copy of a third party package
within the your onepub private repository.  This lets you review and control
how third party packages are used by your app.
