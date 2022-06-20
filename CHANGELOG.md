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
- Fixed bug on windows caused by settgins.yaml trying move the file whilst it was still open.

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
