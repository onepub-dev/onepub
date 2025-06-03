# OnePub

OnePub is a hosted (SAAS) private package repository for Dart and Flutter.

> OnePub is to Dart what NPM is to Javascript

OnePub aims to provide the same experience as pub.dev but for your own private packages only shared within your team.

* A private repository for your Dart and Flutter packages.
* Painless IDE and CLI Integration.
* Watch public and private packages and receive update notices.
* Hosted API documentation for your private packages
* Search both pub.dev and your private packages from one search page.

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

# opub
With Google deprecating the pub command in favour of using `flutter pub` or `dart pub`
we have created a replacement `opub` command for the lazy ones amongst us (like me).

You will also need to use opub to publish to OnePub if you are using a version of Dart pre 2.12.

Our opub command is a very thin wrapper for `flutter pub` and `dart pub` and simply
passes any command line arguments through to `flutter pub` or `dart pub`.


The opub command detects if your project is a flutter (checks your pubspec.yaml)
if found runs:

`flutter pub <args>`

If you have a non-flutter project then we run

`dart pub <args>`


So to use opub command:

```bash
dart pub global activate onepub
opub get
or
opub upgrade --major-version
or
any other pub subcommands and arguments
```

Enjoy.
