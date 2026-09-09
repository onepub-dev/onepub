import '../auth/oidc_http.dart';
import '../onepub_settings.dart';

class OidcExchangeResult {
  OidcExchangeResult({
    required this.accessToken,
    required this.hostedUrl,
    required this.expiresAt,
  });

  final String accessToken;
  final String hostedUrl;
  final DateTime expiresAt;
}

class OidcExchangeApi {
  OidcExchangeApi({OidcHttpClient? http})
      : http = http ?? const OidcHttpClient();

  final OidcHttpClient http;

  Future<OidcExchangeResult> exchange({
    required String assertion,
    String? audience,
  }) async {
    final settings = OnePubSettings.use();
    final endpoint = Uri.parse(settings.onepubWebUrl).resolve(
      '/api/trusted-access/v1/workload/exchange',
    );
    final response = await http.send(
      method: 'POST',
      uri: endpoint,
      allowBadCertificates: settings.allowBadCertificates,
      jsonBody: <String, dynamic>{
        'grant_type': 'urn:ietf:params:oauth:grant-type:token-exchange',
        'subject_token_type': 'urn:ietf:params:oauth:token-type:jwt',
        'subject_token': assertion,
        if (audience != null && audience.isNotEmpty) 'audience': audience,
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final description = response.body['error_description'];
      throw FormatException(description is String && description.isNotEmpty
          ? description
          : 'OnePub rejected the workload identity.');
    }
    final accessToken = response.body['access_token'];
    final hostedUrl = response.body['hosted_url'];
    final expiresAt = DateTime.tryParse('${response.body['expires_at']}');
    if (accessToken is! String || hostedUrl is! String || expiresAt == null) {
      throw const FormatException(
        'OnePub returned an invalid OIDC exchange response.',
      );
    }
    return OidcExchangeResult(
      accessToken: accessToken,
      hostedUrl: hostedUrl,
      expiresAt: expiresAt,
    );
  }
}
