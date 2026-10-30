import 'dart:convert';

import 'package:onepub/src/api/auth_response.dart';
import 'package:onepub/src/exceptions.dart';
import 'package:onepub/src/util/bread_butter_auth.dart';
import 'package:onepub/src/util/send_command.dart';
import 'package:test/test.dart';

AuthResponse response(int status, Map<String, dynamic> body,
        {String? retryAfter}) =>
    AuthResponse.parse(EndpointResponse(
      status,
      StringBuffer(jsonEncode(body)),
      CommandType.cli,
      retryAfter: retryAfter,
    ));

void main() {
  test('login waits for rate limit and ordinary poll intervals', () async {
    final replies = [
      response(429, {'error': 'Too many login requests'}, retryAfter: '8'),
      response(200, {
        'body': {'status': 'retry', 'pollInterval': 3}
      }),
      response(200, {
        'body': {
          'status': 'authSucceeded',
          'onePubToken': 'token',
          'firstLogin': false,
          'operatorEmail': 'member@example.test',
          'organisationName': 'Test Org',
          'obfuscatedOrganisationId': 'test-org',
        }
      }),
    ];
    var clock = DateTime.utc(2026);
    final waits = <Duration>[];
    final events = <String>[];

    final result = await waitForLoginResponse(
      () async {
        events.add('poll');
        return replies.removeAt(0);
      },
      onReady: () => events.add('show link'),
      now: () => clock,
      delay: (duration) async {
        waits.add(duration);
        events.add('wait');
        clock = clock.add(duration);
      },
    );

    expect(result.status, AwaitLoginStatus.authSucceeded);
    expect(waits, [const Duration(seconds: 8), const Duration(seconds: 3)]);
    expect(events, ['poll', 'wait', 'poll', 'show link', 'wait', 'poll']);
  });

  test('repeated rate limits end the login attempt after two minutes',
      () async {
    var clock = DateTime.utc(2026);
    var polls = 0;

    await expectLater(
      waitForLoginResponse(
        () async {
          polls++;
          return response(429, {'error': 'Too many login requests'},
              retryAfter: '60');
        },
        now: () => clock,
        delay: (duration) async => clock = clock.add(duration),
      ),
      throwsA(isA<ExitException>()),
    );
    expect(polls, 2);
  });

  test('repeated HTTP 429 responses slow subsequent login polls', () async {
    var clock = DateTime.utc(2026);
    var polls = 0;
    final waits = <Duration>[];

    final result = await waitForLoginResponse(
      () async {
        polls++;
        if (polls < 3) {
          return response(429, {'error': 'Too many login requests'},
              retryAfter: '1');
        }
        return response(200, {
          'body': {
            'status': 'authSucceeded',
            'onePubToken': 'token',
            'firstLogin': false,
            'operatorEmail': 'member@example.test',
            'organisationName': 'Test Org',
            'obfuscatedOrganisationId': 'test-org',
          }
        });
      },
      now: () => clock,
      delay: (duration) async {
        waits.add(duration);
        clock = clock.add(duration);
      },
    );

    expect(result.status, AwaitLoginStatus.authSucceeded);
    expect(waits, [const Duration(seconds: 3), const Duration(seconds: 6)]);
  });
}
