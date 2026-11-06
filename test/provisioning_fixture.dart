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
  ProvisioningFixture({Map<String, dynamic>? browserAuthorization})
      : _browserAuthorization = browserAuthorization;

  final Map<String, dynamic>? _browserAuthorization;
  static final _clients = <String, Future<_ProvisioningBootstrap>>{};
  static const _mappedRoles = {'Collaborator', 'TeamLeader', 'Uploader'};

  Future<Map<String, dynamic>> createOrganisation({
    required String name,
    required String plan,
  }) async {
    final settings = OnePubSettings.use();
    final url = assertSafeOnePubTestUrl(
        settings.onepubUrl ?? OnePubSettings.defaultOnePubUrl,
        source: 'organisation fixture');
    return await _resourceRequest(
        url, await OnePubTokenStore().load(), 'TestOrganisations', {
      'schemas': ['urn:onepub:params:scim:schemas:test:2.0:Organisation'],
      'name': name,
      'plan': plan,
      'dedicatedOwner': true,
    });
  }

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
    final _ProvisioningBootstrap bootstrap;
    try {
      bootstrap = await (_clients[key] ??= _bootstrap(url, token));
    } on Object {
      _clients.removeWhere((candidate, _) => candidate == key);
      rethrow;
    }
    final scim = bootstrap.client;
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
    if (_mappedRoles.contains(role)) {
      final group = bootstrap.roleGroups[role];
      if (group == null || group.isEmpty) {
        throw const ScimTestException('Missing approved role mapping.');
      }
      // Membership uses the production protocol; bind only proves synthetic
      // ownership and accepts terms. Approved roles are projected by SCIM.
      await scim.addGroupMember(group, id);
    }
    return _createResponse(await _fixtureRequest(
        url, token, 'bind', {'scimId': id, 'role': role}));
  }

  Future<_ProvisioningBootstrap> _bootstrap(String url, String token) async {
    final configured = _browserAuthorization ?? _authorizationFromEnvironment();
    final advanced = configured == null &&
        Platform.environment['ONEPUB_TEST_SCIM_ADVANCED_CLIENT_CREDENTIALS'] ==
            'true';
    if (configured == null && !advanced) {
      throw const ScimTestException('Browser SCIM authorization is required.');
    }
    final body = await _fixtureRequest(
        url, token, 'bootstrap', {'advancedClientCredentials': advanced});
    final roleGroups = body['roleGroups'];
    if (roleGroups is! Map<String, dynamic> ||
        !_mappedRoles.every((role) =>
            roleGroups[role] is String &&
            (roleGroups[role] as String).isNotEmpty)) {
      throw const ScimTestException('Invalid approved role mappings.');
    }
    final ScimTestClient client;
    if (configured != null) {
      for (final key in [
        'clientId',
        'clientSecret',
        'authorizationCode',
        'redirectUri'
      ]) {
        if (configured[key] is! String || (configured[key] as String).isEmpty) {
          throw const ScimTestException('Invalid browser SCIM authorization.');
        }
      }
      client = ScimTestClient.authorizationCode(
          onepubUrl: url,
          clientId: configured['clientId'] as String,
          clientSecret: configured['clientSecret'] as String,
          authorizationCode: configured['authorizationCode'] as String,
          redirectUri: configured['redirectUri'] as String,
          codeVerifier: configured['codeVerifier'] as String?);
      await client.refresh();
    } else {
      if (body['clientId'] is! String || body['clientSecret'] is! String) {
        throw const ScimTestException('Invalid advanced client credentials.');
      }
      client = ScimTestClient.clientCredentials(
          onepubUrl: url,
          clientId: body['clientId'] as String,
          clientSecret: body['clientSecret'] as String);
    }
    return _ProvisioningBootstrap(client,
        {for (final role in _mappedRoles) role: roleGroups[role] as String});
  }

  Map<String, dynamic>? _authorizationFromEnvironment() {
    final encoded = Platform.environment['ONEPUB_TEST_SCIM_AUTHORIZATION'];
    if (encoded == null) {
      return null;
    }
    try {
      final value = jsonDecode(encoded);
      if (value is Map<String, dynamic>) {
        return value;
      }
    } on FormatException {
      // Never expose one-use codes or client credentials from malformed JSON.
    }
    throw const ScimTestException('Invalid browser SCIM authorization.');
  }

  MemberCreate _createResponse(Map<String, dynamic> resource) =>
      MemberCreate(EndpointResponse(HttpStatus.ok,
          StringBuffer(jsonEncode({'body': resource})), CommandType.cli));

  Future<Map<String, dynamic>> _fixtureRequest(String url, String token,
          String operation, Map<String, dynamic> body) =>
      _resourceRequest(url, token, 'TestProvisioningFixtures', {
        'schemas': ['urn:onepub:params:scim:schemas:test:2.0:Fixture'],
        'operation': operation,
        ...body,
      });

  Future<Map<String, dynamic>> _resourceRequest(String url, String token,
      String resource, Map<String, dynamic> body) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      return await (() async {
        final request = await client
            .postUrl(Uri.parse(url).replace(path: '/api/scim/v2/$resource'));
        request.followRedirects = false;
        request.headers
          ..contentType = ContentType.json
          ..set(HttpHeaders.authorizationHeader, 'Bearer $token');
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

class _ProvisioningBootstrap {
  _ProvisioningBootstrap(this.client, this.roleGroups);

  final ScimTestClient client;
  final Map<String, String> roleGroups;
}
