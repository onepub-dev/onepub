[![Better Uptime Badge](https://betteruptime.com/status-badges/v1/monitor/e98h.svg)](https://betteruptime.com/?utm_source=status_badge)

# OnePub

The offical support site for OnePub.

OnePub is a hosted (SAAS) private package repository for Dart and Flutter.

OnePub is to Dart what NPM is to JavaScript.

To take it for a spin by registering at:
[https://onepub.dev](https://onepub.dev/drive/24a98144-21dd-425f-9c0e-827bb5d28b6e)


Read our blogs on [getting started publishing](https://onepub.dev/drive/73982f1b-4cee-4679-8043-ae5f2ee7330c) to OnePub.


# Documentation
Full documentation is available at:

https://docs.onepub.dev

# Installing
To install onepub run:

```bash
dart pub global activate onepub
onepub login
```
The `onepub login` command will register you with OnePub.


# Support
Read our [FAQ](https://onepub.dev/drive/235a56e4-fbc2-4e56-8442-e57dc357cd8a) for a collection of howtos.

Raise a github [issue](https://github.com/onepub-dev/onepub/issues) for bugs or features.

For general dicsussions and 'how to' information join our github [discussion](https://github.com/onepub-dev/onepub/discussions) groups.

# opub

With Google deprecating the pub command in favour of using `flutter pub` or `dart pub`
we have created a replacement `opub` command for the lazy ones amoungst us (like me).

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


# Security Policy
Details on our [Security Policy](https://github.com/onepub-dev/onepub/blob/master/SECURITY.md)

