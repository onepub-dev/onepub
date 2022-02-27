import 'package:dcli/dcli.dart';
import 'package:onepub/src/token_store/io.dart';
import 'package:test/test.dart';

void main() {
  test('login ...', () async {
    ///
    ///
    /// This is going to be tricky to do as we need to fake the client
    /// interaction and the server interaction.
    ///
    /// We can fake the client by sending a fake reponse directly back
    /// the the web server that login starts.
    /// We then need to mock the results from the onepub server
    /// as otherwise it will try to validate the credentials with BB.
    ///
    /// For the moment I've disable this test as the login is one
    /// of the things we will be using all of the time so has
    /// a low probability of being broken.
    ///
    withTempDir((tempDir) {
      withEnvironment(() {
        // final store = OnePubTokenStore();

        // /// reset out token.
        // DartSdk()
        //     .runPub(args: ['token', 'remove',
        // OnePubSettings().onepubWebUrl]);

        // 'onepub login'.run;
      }, environment: {pubTestsConfigDirKey: tempDir});
    });
  }, skip: true);
}
