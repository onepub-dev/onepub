import '../util/send_command.dart';
import 'cli_models.dart';

class OnePubToken {
  String? token;

  String? errorMessage;

  OnePubToken(EndpointResponse response) {
    if (response.success) {
      token = response.requireCliBody(CliExportTokenBody.fromJson).onepubToken;
    }

    if (token == null) {
      errorMessage = response.errorMessage;
    }
  }

  bool get success => token != null;
}
