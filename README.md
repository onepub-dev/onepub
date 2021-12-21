# pub 

With Google deprecating the pub command in favour of using `flutter pub` or `dart pub`
we have created a replacement `pub` command for the lazy ones amoungst us (like me).

Our pub command is a very thin wrapper for `flutter pub` and `dart pub` and simply
passes any command line arguments through to `flutter pub` or `dart pub`.


The pub command detects if you have flutter installed (is it on your PATH?) and
if found runs:

`flutter pub <args>`

If flutter isn't on your PATH then we run

`dart pub <args>`

As most people have flutter installed but still may have need to run the `dart pub` command
then you can use `pubd <args>` which will always run `dart pub`.

So to use pub command:

```bash
dart pub global activate onepub
pub get
or
pub upgrade --major-version
or
any other pub subcommands and arguments
```

Enjoy.


