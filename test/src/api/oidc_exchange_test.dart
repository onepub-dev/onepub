import 'dart:io';

import 'package:onepub/src/api/oidc_exchange.dart';
import 'package:onepub/src/auth/oidc_http.dart';
import 'package:onepub/src/onepub_settings.dart';
import 'package:test/test.dart';

void main() {
  test('exchanges a JWT without overriding its provider-issued audience',
      () async {
    final temp = Directory.systemTemp.createTempSync('onepub-oidc-exchange-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final http = _FakeHttp();

    await OnePubSettings.withPathTo<void>(temp.path, () async {
      final result = await OidcExchangeApi(http: http).exchange(
        assertion: 'header.payload.signature',
      );

      expect(result.accessToken, 'onepub-token');
      expect(result.hostedUrl, 'https://onepub.dev/api/organisation/');
      expect(result.expiresAt, DateTime.utc(2026, 8, 7, 12));
      expect(
        http.uri.toString(),
        'https://onepub.dev/api/trusted-access/v1/workload/exchange',
      );
      expect(http.jsonBody, isNot(contains('audience')));
      expect(http.jsonBody['subject_token'], 'header.payload.signature');
    });
  });
}

class _FakeHttp extends OidcHttpClient {
  late Uri uri;
  Map<String, dynamic> jsonBody = {};

  @override
  Future<OidcHttpResponse> send({
    required String method,
    required Uri uri,
    Map<String, String> headers = const {},
    Map<String, dynamic>? jsonBody,
    bool allowBadCertificates = false,
  }) async {
    this.uri = uri;
    this.jsonBody = jsonBody ?? {};
    return OidcHttpResponse(200, {
      'access_token': 'onepub-token',
      'hosted_url': 'https://onepub.dev/api/organisation/',
      'expires_at': '2026-08-07T12:00:00Z',
    });
  }
}
