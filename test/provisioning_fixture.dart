import 'dart:convert';
import 'dart:io';

import 'package:onepub/src/api/member_create.dart';
import 'package:onepub/src/onepub_settings.dart';
import 'package:onepub/src/util/one_pub_token_store.dart';
import 'package:onepub/src/util/send_command.dart';

import 'scim_test_client.dart';
import 'test_settings.dart';

/// Isolated identity ownership and role setup, separate from SCIM privileges.
///
/// The server must enforce its test-endpoint gates on these bootstrap routes.
/// Each human is first provisioned through real OAuth-authenticated SCIM.
class ProvisioningFixture {
  static final _clients = <String, Future<ScimTestClient>>{};

  Future<MemberCreate> createMember({
    required String userEmail,
    required String firstname,
    required String lastname,
    required String role,
  }) async {
    final settings = OnePubSettings.use();
    final url = assertSafeOnePubTestUrl(
        settings.onepubUrl ?? OnePubSettings.defaultOnePubUrl,
        source: 'provisioning fixture');
    final token = await OnePubTokenStore().load();
    if (role == 'CICD') {
      return _createResponse(
          await _fixtureRequest(url, token, 'service-account', {
        'email': userEmail,
        'firstname': firstname,
        'lastname': lastname,
        'role': role,
      }));
    }

    // Never reuse a client across an organisation or operator identity change.
    final key = '$url|${settings.obfuscatedOrganisationId}|$token';
    final ScimTestClient scim;
    try {
      scim = await (_clients[key] ??= _bootstrap(url, token));
    } on Object {
      _clients.removeWhere((candidate, _) => candidate == key);
      rethrow;
    }
    final existing = await scim.findUsers(userEmail);
    if (existing.length > 1) {
      throw const ScimTestException('Ambiguous test provisioning identity.');
    }
    Map<String, dynamic> user;
    if (existing.isNotEmpty) {
      user = existing.single;
    } else {
      try {
        user = await scim.createUser(
            email: userEmail, firstname: firstname, lastname: lastname);
      } on ScimTestException catch (error) {
        if (error.status != HttpStatus.conflict) {
          rethrow;
        }
        // A prior POST may have committed before the client lost its response.
        final found = await scim.findUsers(userEmail);
        if (found.length != 1) {
          rethrow;
        }
        user = found.single;
      }
    }
    final id = user['id'];
    if (id is! String || id.isEmpty) {
      throw const ScimTestException('Missing test provisioning identity.');
    }
    return _createResponse(await _fixtureRequest(
        url, token, 'bind', {'scimId': id, 'role': role}));
  }

  Future<ScimTestClient> _bootstrap(String url, String token) async {
    final response = await _fixtureRequest(url, token, 'bootstrap', {});
    final body = response['body'];
    if (body is! Map<String, dynamic> ||
        body['clientId'] is! String ||
        body['clientSecret'] is! String) {
      throw const ScimTestException('Invalid provisioning bootstrap response.');
    }
    return ScimTestClient(
        onepubUrl: url,
        clientId: body['clientId'] as String,
        clientSecret: body['clientSecret'] as String);
  }

  MemberCreate _createResponse(Map<String, dynamic> envelope) =>
      MemberCreate(EndpointResponse(
          HttpStatus.ok, StringBuffer(jsonEncode(envelope)), CommandType.cli));

  Future<Map<String, dynamic>> _fixtureRequest(String url, String token,
      String operation, Map<String, dynamic> body) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      return await (() async {
        final request = await client.postUrl(
            Uri.parse(url).replace(path: '/api/test/provisioning/$operation'));
        request.followRedirects = false;
        request.headers
          ..contentType = ContentType.json
          ..set(HttpHeaders.authorizationHeader, token);
        request.write(jsonEncode(body));
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok &&
            response.statusCode != HttpStatus.created) {
          throw ScimTestException('Provisioning fixture failed.',
              status: response.statusCode);
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > 1024 * 1024) {
            throw const ScimTestException(
                'Fixture response exceeds size limit.');
          }
          bytes.addAll(chunk);
        }
        final envelope = jsonDecode(utf8.decode(bytes));
        if (envelope is! Map<String, dynamic>) {
          throw const ScimTestException(
              'Invalid provisioning fixture response.');
        }
        return envelope;
      })()
          .timeout(const Duration(seconds: 30));
    } on ScimTestException {
      rethrow;
    } on Object {
      // Bootstrap responses contain one-time secrets; never print raw bodies.
      throw const ScimTestException('Provisioning fixture request failed.');
    } finally {
      client.close(force: true);
    }
  }
}
