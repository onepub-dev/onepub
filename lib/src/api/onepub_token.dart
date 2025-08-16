import '../util/send_command.dart';

class OnePubToken {
  String? token;

  String? errorMessage;

  OnePubToken(EndpointResponse response) {
    if (response.success) {
      token = response.data['onepubToken'] as String?;
    }

    if (token == null) {
      errorMessage = response.data['message']! as String;
    }
  }

  bool get success => token != null;
}
