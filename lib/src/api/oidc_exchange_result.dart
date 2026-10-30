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
