# 6.0.0
- removed support for opub as dart 2.15 is long gone. If you still
 need opub then install a 4.x version.
- fixed a compatibility issue with dart 3.9.0

# 5.0.0
- Upgraded package deps to support dart 3.5
- replaced deprecated call to  UnmodifiableUnit8ListView

# 4.2.0
- upgraded dependencies dcli, pubspec_manager and settings_yaml
- Fixed the welcome message link to getting-started which didn't exist
 now points to the my first package blog.

# 4.1.0
- support for dart 3.2 +

# 4.1.0-beta.1
- support for dart 3.2.x

# 3.1.0-beta.1
- moved some dependencies into the dev_dependencies section to help
with Dart 3.x compatibility.

# 3.0.3
- Upgraded to pub_semver 2.1.2 to resolve a dart 2.19 incompatibility issue.

# 3.0.2
- upgraded to file 6.1.4 so that we are dart 2.19 compatible.
- updated to lint_hard 3.x
- restored the major version no. check, now we have upgraded the server to 3.x

# 3.0.1
Remove the major version check until further notice.

# 3.0.0
BREAKING: the REST API used by the export command has change the name of its end point.
An upgrade of the CLI tooling to 3.x is required.

# 2.0.5
- removed the fvm dependency as we don't need to use it.
- Fixes: #193 a bug in doctor when the users path includes a blank path. Thanks to @ahmendnfwela for reporting the issue.
- run dcli lock to fix all versions to a specific versions (including transient dependencies) to ensure our code is stable in the face of a dependency being upgraded in a way that breaks onepub on the customer system.
- Fixed the user agent so the onepub commands always present as being at least dart 2.15.0 so the server won't reject our requests.
- Modified the user-agent we pass as it must always contain a version of at least 2.15.0 otherwise the server will reject the request.
- Added a fix for io runProcessSync as the publish command was passing down an empty string for the working directory when they really meant null to indicate the cwd.  We now detect an empty string and substitute null. This fixes the 'git' file not found error (which was that the working directory couldn't be found).
- removed the ssh related instructions.
- Changed doctor to print the dart version first.


# 2.0.4
- upgraded to scope 3.0.0 as need a bug fix for async calls to Scope.run (it wouldn't wait). This required an upgrade to dcli 1.21.0 as it dependes on scope 3.0.0
- Added additional tests for the import command - still not fully tested.
- Change the import token regext to reflect tha tokens are no longer 36 chars long. Expected length i snow 56 chars.
- fix for login error message display
- Added code to log http headers when sending command and debug mode is enabled.

# 2.0.3
- update dcli

# 2.0.2
- update dcli

# 2.0.1
- Added logging of data received in both hex and ascii.
- added locale to onepub doctor.

# 2.0.0
- BREAKING: re-wrote login to use pure server side rather than requiring the browser to connect via local host. This is to get around local firewalls, the brave browser and the inability to login from an ssh session or a local docker container. All of these scenarios should now work.
- Added version checks into the api to ensure the onepub client is running
  against a compatible onepub client.
- doctor now checks for a compatible server version no.
- improvements to the auth pre test hook.
- Added missing future/await to return of withTestSystem callback.
- renamed OnePubTokenStore.fetch to load as fetch implies an http request rather then a local file.
- moved to dcli 1.20.2 as 1.20.1 didn't actually correctly support dart 2.12 whilst 1.20.2 does.
- Added unit test for missing sub command.
- Change the structure of the REST json response from onepub to expect 'body' rather than 'success' for the body of the response.
- Added capture function from dcli 2.x to help with unit testing.
- Added ExitException to list of user facing exceptions.
- Changed logout json response to always have non-null error message.
- Added missing awaits after testing code against dart 2.18 improved formatting of usage statements. Improved formatting/messaging of errors.
- Added the .pub-cache path to the doctor output.
- improved the formatting of the doctor command.

# 1.4.5
- Modified the ssh detection and removed SSH_AGENT_PID as this is
  used on the local machine to indicate the PID of the local ssh agent
  and not an indicator that we are in an ssh session.

# 1.4.4
- Updated the pubspec description.

# 1.4.3
- updated the readme to make it more suitable for pub.dev.
- Added additional diagnostic details to onepub doctor.
- changed doctor to refer to the member and organisation as the 'Active' member and organisation to reflect that we can be logged into multiple organisations.

# 1.4.2
- Added docker shell detection to the login command with instructions on how work with docker.
- Fixed the path to the ssh guide in the login error.
- Improved the cli login message.

# 1.4.1
- fix: null check error when token has expired and we attempt to get the organisation via the api.
- Improved the onepub doctor message when PUB_CACHE isn't set.

# 1.4.0
- added ability to create a member for testing during the unit test auth.
- delete tool dir so analysis runs.

# 1.3.2
- fixed a 'first time' bug with the login.

# 1.3.1
- Fixed errors raised by the static analyzer.

# 1.3.0
- applied lint_hard
- renamed add_private to add.
- restructured the command set so all package related commands are under pub.
- Improvements to the help output and general cli output from each command.
- Added PATH to the output of onepub doctor.
- Updated license files to reflect actual and intended usage.
- Added global deactivate. change command structure of global to be pub global to match dart pub commands.
- Added onepub global activate command to make it easy to activate packages hosted by onepub.
- upgraded third party tar library.
- Now saving the opeartor email into the OnePubSettings file so that onepub doctor can print it out.
- Fixed spelling in login for failed auth.
- colour coded the error message displayed by onepub login when you try to use it from an ssh shell.
- improved unit tests.

# 1.2.4
- Fixes #37

# 1.2.2
- Added documentation keyword to pubspec.yaml

# 1.2.1
- Tweaks to improve our pub.dev score.

# 1.2.0
- removed the need to pass a version to the onepub add command.

# 1.1.12
- import command now sets the organisation name.
- change logout command so it succeeds even if you have already logged out.
- change import to use the new end point /organisation/token.
- fixes for windows.

# 1.1.11
- Added a --ask switch to import so a user could directly enter the onepub token. This was to make it easy for ssh users to authenticate.
- improvements to the output of onepub doctor.

# 1.1.10
- minor cleanups.

# 1.1.9
- improved the completion message when adding a private dependency.
- Found a combo dependencies that works from 2.12 to 2.17. Change dependencies with care.
- change resolveWebEndPoint to use the correct slash when running on windows.
- Fixed bug on windows caused by settings.yaml trying move the file whilst it was still open.

# 1.1.7
- Merge branch 'main' of github.com:onepub-dev/onepub
- add CORS header
- Merge branch 'main' of github.com:onepub-dev/onepub
- Fixed a bug in dart 'pub login' command when google auth doesn't return the name field.
- Update release.yml
- tidy up
- remove print statements

# 1.1.0
Asper KayZGames recommendation we now check for a flutter dependency in the pubspec.yaml
to determine if we should run flutter pub or dart pub.

# 1.0.2
Better description.

# 1.0.1
- spelling

# 1.0.0
- First release

## 0.0.1
- Initial version.
