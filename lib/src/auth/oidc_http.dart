import 'dart:convert';
import 'dart:io';

class OidcHttpResponse {
  OidcHttpResponse(this.statusCode, this.body);

  final int statusCode;
  final Map<String, dynamic> body;
}

class OidcHttpClient {
  const OidcHttpClient();

  Future<OidcHttpResponse> send({
    required String method,
    required Uri uri,
    Map<String, String> headers = const {},
    Map<String, dynamic>? jsonBody,
    bool allowBadCertificates = false,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..userAgent = 'onepub-oidc';
    if (allowBadCertificates) {
      client.badCertificateCallback = (_, __, ___) => true;
    }
    try {
      final HttpClientRequest request;
      if (method == 'GET') {
        request = await client.getUrl(uri);
      } else if (method == 'POST') {
        request = await client.postUrl(uri);
      } else {
        throw ArgumentError.value(method, 'method', 'Unsupported HTTP method');
      }
      headers.forEach(request.headers.set);
      if (jsonBody != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(jsonBody));
      }
      final response = await request.close();
      final text = await utf8.decoder.bind(response).join();
      final Object? decoded = text.trim().isEmpty ? null : jsonDecode(text);
      return OidcHttpResponse(
        response.statusCode,
        decoded is Map ? Map<String, dynamic>.from(decoded) : {},
      );
    } finally {
      client.close(force: true);
    }
  }
}
