# OnePub CLI

OnePub is a private package repository for Dart and Flutter teams. The `onepub` CLI helps you sign in, publish private packages, and add them to your projects. You can continue to use the standard Dart and Flutter tooling to publish and fetch packages.

For setup guides and the full command reference, see the [OnePub manual](https://docs.onepub.dev).

## Register your OnePub account

Go to [Register][https://onepub.dev] and click the Sign In/Sign Up link in the top right hand corner.



## Install and sign in

Once you have registered with OnePub:


```sh
dart pub global activate onepub
onepub login
```

`onepub login` prints a URL. Open it in a browser and complete sign-in within five minutes. You can open the URL on another device when using SSH or a terminal without a browser.

For enterprise SSO, use the organisation code supplied by your administrator:

```sh
onepub login sso acme
```

After a successful sign-in, `onepub login` remembers the method and organisation for that OnePub server. Use `onepub login --choose` to choose again, or `onepub login browser` for ordinary browser sign-in. Enterprise SSO requires a supporting OnePub server.

`onepub logout` retains the remembered method. Use `onepub logout --forget` to remove it too. A failed sign-in keeps your previous login.

For CI with trusted publishing, configure it in OnePub and use `onepub login trusted`. Run `onepub login trusted --help` for its options.

Trusted Publishing is configured 'per package' on the My OnePub | Managed Packages page. Select a package then click the 'Trusted Publishing' tab.

## Publish a private package

From your package directory, mark the package as private and publish it:

```sh
onepub pub private
dart pub publish
```

The `onepub pub private` command sets the package's `publish_to` URL in the `pubspec.yaml` to your OnePub organisation.

For a Flutter package, you can use `flutter pub publish`. 

## Add a private dependency

You can add a dependency in your dart/flutter project to a private package that you have hosted on OnePub.

From the directory of the project that needs the package, run:

```sh
onepub pub add my_private_package
```

This adds the private package to your project's `pubspec.yaml` and fetches it.

## Other useful commands

| Command | Purpose |
| --- | --- |
| `onepub doctor` | Show your OnePub configuration and connection status. |
| `onepub pub global activate <package>` | Make a private package's executables available globally. |
| `onepub pub global deactivate <package>` | Remove a globally activated package. |
| `onepub logout` | Sign out of the OnePub CLI on all your devices. |
| `onepub --help` | List commands and options. |

For detailed workflows, authentication options, and command usage, read the [OnePub manual](https://docs.onepub.dev).
