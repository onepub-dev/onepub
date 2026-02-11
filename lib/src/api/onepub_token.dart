import '../util/send_command.dart';
import 'cli_models.dart';

class OnePubToken {
  String? token;

  String? errorMessage;

  OnePubToken(EndpointResponse response) {
    if (response.success) {
      final envelope = response.parseCli(CliExportTokenBody.fromJson);
      token = envelope.body?.onepubToken;
    }

    if (token == null) {
      errorMessage = response.errorMessage;
    }
  }

  bool get success => token != null;
}
