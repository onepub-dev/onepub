import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:dcli/dcli.dart';

import '../exceptions.dart';
import '../onepub_settings.dart';
import '../util/one_pub_token_store.dart';
import '../util/send_command.dart';
import 'bbauth.dart';

/// onepub login
/// We trigger oauth by showing url
// We then do a long poll to the server and wait for oauth to complete
// The long poll adds a pending request to a guava cache (with expiry)

// The oath completes on the server
// The server checks if there is an existing onepub token for the member
// If so we return the token as this allows mulitple devices to be authed.
// If not we create a new onepub token
// We return the onpub token to the cli and it stores it.
// The cli then passed the onepub token each time it needs to interact.
// No oauth is required we just check the onepub token is invalid.
// A logout on any device will invalidate the token.
// A manager can invalidate the token from the web site.
class LoginCommand extends Command<void> {
  ///
  LoginCommand();

  @override
  String get description => 'Log in to onepub.dev.';

  @override
  String get name => 'login';

  @override
  Future<void> run() async {
    loadSettings();

    try {
      final tempAuthTokenResponse = await bbAuth();
      if (tempAuthTokenResponse == null) {
        throw ExitException(
            exitCode: 1, message: 'Invalid response. onePubToken not returned');
      }

      if (tempAuthTokenResponse.success) {
        final tempAuthToken =
            tempAuthTokenResponse.data['tempAuthToken']! as String;
        final operatorEmail =
            tempAuthTokenResponse.data['operatorEmail']! as String;

        final candidates = await fetchCandidates(
            tempAuthToken: tempAuthToken, operatorEmail: operatorEmail);

        Candidate candidate;

        if (candidates.length > 1) {
          candidate = selectCandidate(candidates);
        } else {
          candidate = candidates[0];
        }

        await finaliseAuth(
            tempAuthToken: tempAuthToken,
            candidate: candidate,
            operatorEmail: operatorEmail);
      } else {
        showError(tempAuthTokenResponse);
      }
    } on FetchException {
      printerr(red('Unable to connect to the onepub.dev server. '
          'Check your internet connection.'));
    }
  }

  Future<void> finaliseAuth(
      {required String tempAuthToken,
      required String operatorEmail,
      required Candidate candidate}) async {
    final response = await sendCommand(
      command: 'authMember'
          '/$tempAuthToken'
          '/$operatorEmail'
          '/${candidate.isInvite}'
          '/${candidate.obfuscatedPublisherId}',
      authorised: false,
    );

    if (response.success) {
      final onepubToken = response.data['onePubToken'] as String?;
      final firstLogin = response.data['firstLogin'] as bool?;
      if (onepubToken == null || firstLogin == null) {
        throw ExitException(
            exitCode: 1,
            message: 'Invalid response. authToken or firstLogin missing');
      }
      OnePubTokenStore().save(
          onepubToken: onepubToken,
          obfuscatedPublisherId: candidate.obfuscatedPublisherId);
      OnePubSettings()
        ..publisherName = candidate.publisherName
        ..save();

      showWelcome(
          firstLogin: firstLogin, publisherName: candidate.publisherName);
    } else {
      showError(response);
    }
  }

  void showError(EndpointResponse endPointResponse) {
    final error = endPointResponse.data['message']! as String;

    print(red(error));
  }

  Future<List<Candidate>> fetchCandidates(
      {required String tempAuthToken, required String operatorEmail}) async {
    final response = await sendCommand(
      command: 'candidates'
          '/$tempAuthToken/$operatorEmail',
      authorised: false,
    );

    if (!response.success) {
      throw ExitException(
          exitCode: 1, message: response.data['message']! as String);
    }

    final list = response.data['candidates']! as List;
    final candidates = List<Candidate>.from(
        list.map<Candidate>((dynamic data) => Candidate.fromJson(data)));

    return candidates;
  }

  Candidate selectCandidate(List<Candidate> candidates) {
    print('');
    print(blue('Your email is associated with multiple publishers.'));
    return menu(
        prompt: 'Select the Publisher:',
        options: candidates,
        format: (candidate) {
          var name = candidate.publisherName;
          if (candidate.isInvite) {
            name += ' - Invitation';
          }
          return name;
        });
  }
}

class Candidate {
  Candidate(this.publisherName, this.obfuscatedPublisherId,
      {required this.isInvite});

  factory Candidate.fromJson(dynamic data) {
    final json = data as Map<String, dynamic>;
    final publisherName = json['publisherName'] as String;
    final isInvite = json['isInvite'] as bool;
    final obfuscatedPublisherId = json['obfuscatedPublisherId']! as String;

    return Candidate(publisherName, obfuscatedPublisherId, isInvite: isInvite);
  }

  String publisherName;
  bool isInvite;
  String obfuscatedPublisherId;
}

void showWelcome({required bool firstLogin, required String publisherName}) {
  var firstMessage = '';
  if (firstLogin) {
    firstMessage = '''
Welcome to OnePub.
Read the getting started guide at:
${orange('https://onepub.dev/getting-started')}

''';
  }

  print('''

${blue('Successfully logged into $publisherName.')}

$firstMessage
''');
}
