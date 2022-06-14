# OnePub

The offical support site for OnePub the hosted private package repository for Dart and Flutter.

OnePub is to Dart what NPM is to JavaScript and JFrog to Java.

OnePub lets you use the existing Dart tooling (dart pub publish | flutter pub publish) to publish packages to your own private repository.

OnePub includes a free plan for personal use.

To take it for a spin register at:
https://onepub.dev

Full documentation is available at:

https://docs.onepub.dev


## opub

With Google deprecating the pub command in favour of using `flutter pub` or `dart pub`
we have created a replacement `opub` command for the lazy ones amoungst us (like me).


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

