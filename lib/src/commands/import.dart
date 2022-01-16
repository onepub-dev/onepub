import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';

import '../exceptions.dart';
import '../util/credentials.dart';

///
class ImportCommand extends Command<void> {
  ///
  ImportCommand() : super() {
    argParser.addFlag('secret',
        abbr: 's',
        help: 'Imports the secret from the ${Credentials.onepubSecretEnvKey}'
            'environment variable');
  }

  @override
  String get description => '''
Import onepub secret.

  onepub import --secret
  onepub import [<path to credentials>] ''';

  @override
  String get name => 'import';

  @override
  void run() {
    import();
  }

  ///
  void import() {
    final secret = argResults!['secret'] as bool;

    final String oauth2Token;

    if (secret) {
      oauth2Token = fromSecret();
    } else {
      oauth2Token = fromFile();
    }
    env[Credentials.onepubSecretEnvKey] = oauth2Token;

    'dart pub token add https://onepub.dev --env-var ${Credentials.onepubSecretEnvKey}'
        .run;
  }

  /// pull the secret from credentials.yaml
  String fromFile() {
    final String pathToCredentials;
    if (argResults!.rest.length > 1) {
      throw ExitException(exitCode: 1, message: '''
The onepub import command only takes zero or one arguments. 
Found: ${argResults!.rest.join(',')}''');
    }
    if (argResults!.rest.isEmpty) {
      pathToCredentials = argResults!.rest[0];
    } else {
      pathToCredentials = join(pwd, Credentials.credentialsFileName);
    }

    final credentials = Credentials.load(pathToCredentials);

    return credentials.oauth2Token;
  }

  /// pull the secret from an env var
  String fromSecret() {
    print(orange(
        'Importing Onepub secret from ${Credentials.onepubSecretEnvKey}'));

    if (!Env().exists(Credentials.onepubSecretEnvKey)) {
      throw ExitException(exitCode: 1, message: '''
    The onepub environment variable ${Credentials.onepubSecretEnvKey} doesn't exist.
    Have you added it to your CI/CD secrets?.''');
    }

    return env[Credentials.onepubSecretEnvKey]!;
  }
}
