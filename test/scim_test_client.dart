import 'dart:convert';
import 'dart:io';

import 'test_settings.dart';

/// An ordinary OAuth client for the production SCIM protocol on test servers.
///
/// Credentials come from isolated fixture setup, never from a member token.
/// Separate fixtures handle roles, identity ownership and token export.
class ScimTestClient {
  ScimTestClient({
    required String onepubUrl,
    required String clientId,
    required String clientSecret,
  })  : _base = Uri.parse(
            assertSafeOnePubTestUrl(onepubUrl, source: 'SCIM test client')),
        _clientId = clientId,
        _clientSecret = clientSecret {
    if (_base.userInfo.isNotEmpty ||
        _base.hasQuery ||
        _base.hasFragment ||
        clientId.isEmpty ||
        clientSecret.isEmpty) {
      throw ArgumentError('Invalid SCIM test client configuration.');
    }
  }

  final Uri _base;
  final String _clientId;
  final String _clientSecret;
  String? _accessToken;
  DateTime? _expiresAt;

  static const userSchema = 'urn:ietf:params:scim:schemas:core:2.0:User';
  static const groupSchema = 'urn:ietf:params:scim:schemas:core:2.0:Group';
  static const patchSchema = 'urn:ietf:params:scim:api:messages:2.0:PatchOp';

  Future<Map<String, dynamic>> createUser({
    required String email,
    required String firstname,
    required String lastname,
    String? externalId,
  }) =>
      request('POST', 'Users', body: {
        'schemas': [userSchema],
        'userName': email,
        if (externalId != null) 'externalId': externalId,
        'name': {'givenName': firstname, 'familyName': lastname},
        'active': true,
      });

  Future<List<Map<String, dynamic>>> findUsers(String email) =>
      list('Users', filter: 'userName eq ${jsonEncode(email)}');

  Future<Map<String, dynamic>> setActive(String id, {required bool active}) =>
      request('PATCH', 'Users/${Uri.encodeComponent(id)}', body: {
        'schemas': [patchSchema],
        'Operations': [
          {'op': 'replace', 'path': 'active', 'value': active}
        ],
      });

  Future<Map<String, dynamic>> createGroup(String name) =>
      request('POST', 'Groups', body: {
        'schemas': [groupSchema],
        'displayName': name,
        'members': <Map<String, String>>[],
      });

  Future<Map<String, dynamic>> addGroupMember(String groupId, String userId) =>
      request('PATCH', 'Groups/${Uri.encodeComponent(groupId)}', body: {
        'schemas': [patchSchema],
        'Operations': [
          {
            'op': 'add',
            'path': 'members',
            'value': [
              {'value': userId}
            ],
          }
        ],
      });

  /// Reads every page; fixture lookup must work beyond the first 100 users.
  Future<List<Map<String, dynamic>>> list(String resource,
      {String? filter}) async {
    final resources = <Map<String, dynamic>>[];
    var start = 1;
    while (true) {
      final page = await request('GET', resource, query: {
        'startIndex': '$start',
        'count': '100',
        if (filter != null) 'filter': filter,
      });
      final total = page['totalResults'];
      final rows = page['Resources'];
      if (total is! int || total < 0 || rows is! List<dynamic>) {
        throw const ScimTestException('Invalid SCIM list response.');
      }
      for (final row in rows) {
        if (row is! Map<String, dynamic>) {
          throw const ScimTestException('Invalid SCIM resource.');
        }
        resources.add(row);
      }
      if (resources.length >= total) {
        return resources;
      }
      if (rows.isEmpty || resources.length > 10000) {
        throw const ScimTestException('SCIM pagination did not complete.');
      }
      start += rows.length;
    }
  }

  Future<Map<String, dynamic>> request(String method, String resource,
      {Map<String, dynamic>? body, Map<String, String>? query}) async {
    if (!RegExp(r'^[A-Za-z]+(?:/[A-Za-z0-9%_.~-]+)?$').hasMatch(resource)) {
      throw ArgumentError('Invalid SCIM resource path.');
    }
    await _authenticate();
    return await _send(method, '/api/scim/v2/$resource',
        headers: {
          HttpHeaders.authorizationHeader: 'Bearer $_accessToken',
          HttpHeaders.contentTypeHeader: 'application/scim+json',
          HttpHeaders.acceptHeader: 'application/scim+json',
        },
        body: body == null ? null : jsonEncode(body),
        query: query);
  }

  Future<void> _authenticate() async {
    if (_accessToken != null &&
        _expiresAt != null &&
        DateTime.now().isBefore(_expiresAt!)) {
      return;
    }
    final basicCredentials =
        base64Encode(utf8.encode('${Uri.encodeQueryComponent(_clientId)}:'
            '${Uri.encodeQueryComponent(_clientSecret)}'));
    final response = await _send('POST', '/api/provisioning/oauth/token',
        headers: {
          HttpHeaders.authorizationHeader: 'Basic $basicCredentials',
          HttpHeaders.contentTypeHeader: 'application/x-www-form-urlencoded',
          HttpHeaders.acceptHeader: 'application/json',
        },
        body: Uri(queryParameters: {
          'grant_type': 'client_credentials',
          'scope': 'scim',
        }).query);
    final token = response['access_token'];
    final expires = response['expires_in'];
    if (token is! String ||
        token.isEmpty ||
        expires is! int ||
        expires <= 0 ||
        response['token_type'].toString().toLowerCase() != 'bearer') {
      throw const ScimTestException('Invalid provisioning token response.');
    }
    _accessToken = token;
    _expiresAt = DateTime.now()
        .add(Duration(seconds: expires > 10 ? expires - 10 : expires));
  }

  Future<Map<String, dynamic>> _send(String method, String path,
      {required Map<String, String> headers,
      String? body,
      Map<String, String>? query}) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      return await (() async {
        final uri = _base.replace(path: path, queryParameters: query);
        final request = await client.openUrl(method, uri);
        request.followRedirects = false;
        headers.forEach(request.headers.set);
        if (body != null) {
          request.write(body);
        }
        final response = await request.close();
        if (response.statusCode < 200 || response.statusCode >= 300) {
          // Error bodies and redirects may contain secrets or diagnostics.
          throw ScimTestException('SCIM request failed.',
              status: response.statusCode);
        }
        if (response.statusCode == HttpStatus.noContent) {
          return <String, dynamic>{};
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > 4 * 1024 * 1024) {
            throw const ScimTestException('SCIM response exceeds size limit.');
          }
          bytes.addAll(chunk);
        }
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is! Map<String, dynamic>) {
          throw const ScimTestException('Invalid SCIM response.');
        }
        return decoded;
      })()
          .timeout(const Duration(seconds: 30));
    } on ScimTestException {
      rethrow;
    } on Object {
      throw const ScimTestException('SCIM transport or response failed.');
    } finally {
      client.close(force: true);
    }
  }
}

class ScimTestException implements Exception {
  const ScimTestException(this.message, {this.status});

  final String message;
  final int? status;

  @override
  String toString() => status == null ? message : '$message HTTP $status';
}
