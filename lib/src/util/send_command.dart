/* Copyright (C) OnePub IP Pty Ltd - All Rights Reserved
 * licensed under the GPL v2.
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dcli_core/dcli_core.dart';
import 'package:dcli_terminal/dcli_terminal.dart';

import '../exceptions.dart';
import '../onepub_settings.dart';
import 'one_pub_token_store.dart';

class CliMessage {
  final String message;

  CliMessage({required this.message});

  factory CliMessage.fromJson(Map<String, dynamic> json) =>
      CliMessage(message: json['message'] as String? ?? '');
}

class CliError {
  final String message;
  final String? code;

  CliError({required this.message, this.code});

  factory CliError.fromJson(Map<String, dynamic> json) => CliError(
        message: json['message'] as String? ?? '',
        code: json['code'] as String?,
      );
}

class CliEnvelope<T> {
  final T? body;
  final CliMessage? success;
  final CliError? error;

  CliEnvelope({this.body, this.success, this.error});

  bool get isSuccess => body != null || success != null;
}

class PubError {
  final String message;
  final String? code;

  PubError({required this.message, this.code});

  factory PubError.fromJson(Map<String, dynamic> json) => PubError(
        message: json['message'] as String? ?? '',
        code: json['code'] as String?,
      );
}

class PubEnvelope<T> {
  final T? body;
  final PubError? error;

  PubEnvelope({this.body, this.error});

  bool get isSuccess => error == null;
}

enum Method { get, post }

Future<EndpointResponse> sendCommand(
    {required String command,
    required CommandType commandType,
    bool authorised = true,
    Map<String, String> headers = const <String, String>{},
    String? body,
    Method method = Method.get}) async {
  final settings = OnePubSettings.use();
  final resolvedEndpoint = settings.resolveApiEndPoint(command);

  verbose(() => 'Sending command: $resolvedEndpoint');
  verbose(() => 'Sending body: $body');

  final uri = Uri.parse(resolvedEndpoint);

  try {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5)
      // we use 2.15.0 as the agent version to indicate to the server
      // that we are running at least dart 2.15.0 (even if we are not)
      // so it will accept our requests.
      ..userAgent = 'onepub 2.15.0';

    /// allow self signed/staged certs in dev
    if (settings.allowBadCertificates) {
      client.badCertificateCallback = (cert, host, port) => true;
    }

    final response =
        await _startRequest(client, method, uri, headers, body, authorised);

    return await _processData(client, response, commandType);
  } on SocketException catch (e) {
    throw FetchException.fromException(e);
  }
}

Future<HttpClientResponse> _startRequest(HttpClient client, Method method,
    Uri uri, Map<String, String> headers, String? body, bool authorised) async {
  final headers0 = <String, String>{}..addAll(headers);

  if (authorised) {
    if (!await OnePubTokenStore()
        .isLoggedIn(OnePubSettings.use().onepubApiUrl)) {
      throw ExitException(exitCode: 1, message: '''
You must be logged in to run this command.
run: onepub login
  ''');
    }
    final onepubToken = await OnePubTokenStore().load();

    headers0.addAll({'authorization': onepubToken});
  }

  final HttpClientRequest request;
  switch (method) {
    case Method.get:
      request = await client.getUrl(uri);
      _addHeaders(headers0, request);
    case Method.post:
      request = await client.postUrl(uri);
      _addHeaders(headers0, request);
      if (body != null) {
        request.write(body);
      }
  }

  final response = await request.close();

  final responseHeaders = <String, List<String>>{};
  response.headers.forEach((name, values) => responseHeaders[name] = values);
  return response;
}

/// add custom headers to the request object.
void _addHeaders(Map<String, String> headers, HttpClientRequest request) {
  if (headers.isNotEmpty) {
    for (final header in headers.entries) {
      request.headers.add(header.key, header.value, preserveHeaderCase: true);
    }
  }
}

Future<EndpointResponse> _processData(
  HttpClient client,
  HttpClientResponse response,
  CommandType commandType,
) {
  final completer = Completer<EndpointResponse>();

  final body = StringBuffer();

  if (Settings().isVerbose) {
    verbose(() => 'Chunked Transfer Encodeing: '
        '${response.headers.chunkedTransferEncoding}');
    verbose(() => 'Content Length: ${response.headers.contentLength}');
    verbose(() => 'Content Type: ${response.headers.contentType}');
    verbose(() => 'Date: ${response.headers.date}');
    verbose(() => 'Expires: ${response.headers.expires}');
    verbose(() => 'Host: ${response.headers.host}');
    verbose(() =>
        'Persistent Connection: ${response.headers.persistentConnection}');
  }

  // var lengthReceived = 0;
  // final contentLength = response.contentLength;
  // we have a response.

  late StreamSubscription<List<int>> subscription;
  subscription = response.listen(
    (newBytes) {
      /// if we don't pause we get overlapping calls from listen
      /// which causes the [write] to fail as you can't
      /// do overlapping io.
      subscription.pause();

      verbose(() => 'received (hex): ${toHex(newBytes)}');
      verbose(() => 'received (ascii): ${toAscii(newBytes)}');

      /// we have new data to save.
      body.write(utf8.decode(newBytes));

      // lengthReceived += newBytes.length;

      subscription.resume();
    },
    onDone: () async {
      /// down load is complete
      await subscription.cancel();
      client.close();

      completer
          .complete(EndpointResponse(response.statusCode, body, commandType));
    },
    onError: (Object e, StackTrace st) async {
      // something went wrong.
      await subscription.cancel();
      client.close();
      completer.completeError(e, st);
    },
    cancelOnError: true,
  );

  return completer.future;
}

enum CommandType {
  /// api used by the dart pub commands.
  pub,

  /// api used by onepub.
  cli
}

class EndpointResponse {
  CommandType commandType;

  int status;

  final String _body;

  late final bool _success;
  late final String _errorMessage;

  EndpointResponse(this.status, StringBuffer body, this.commandType)
      : _body = body.toString() {
    _parse();
  }

  bool get success => _success;

  String get errorMessage => _errorMessage;

  /// We expect a response of the form:
  /// {"success":{"message":"${OnePubSettings.onepubHostName} status normal."}}
  /// or
  /// {"error":{"bad things."}}

  void _parse() {
    if (commandType == CommandType.cli) {
      _parseCli();
    } else {
      _parsePub();
    }
  }

  void _parseCli() {
    final decoded = _bodyAsJsonMap(_body);
    if (decoded.keys.contains('body') ||
        decoded.keys.contains('success') ||
        decoded.keys.contains('error')) {
      _success =
          decoded.keys.contains('body') || decoded.keys.contains('success');
      if (decoded.keys.contains('error')) {
        _errorMessage =
            CliError.fromJson(_mapFromJson(decoded['error'])).message;
      } else {
        _errorMessage = '';
      }
      return;
    }
    if (decoded.keys.contains('message')) {
      final message = decoded['message'] as String? ?? '';
      if (status >= 400) {
        _success = false;
        _errorMessage = message;
      } else {
        _success = true;
        _errorMessage = '';
      }
      return;
    }
    if (decoded.isEmpty) {
      _success = status < 400;
      _errorMessage = status < 400 ? '' : 'Empty response';
      return;
    }
    throw UnexpectedHttpResponseException(_body);
  }

  // Used to parse responses from 'pub' specific end points
  void _parsePub() {
    if (status == 200) {
      _success = true;
      _errorMessage = '';
      return;
    }
    _success = false;
    final decoded = _bodyAsJsonMap(_body);
    if (decoded.keys.contains('error')) {
      _errorMessage = PubError.fromJson(_mapFromJson(decoded['error'])).message;
    } else {
      _errorMessage = '';
    }
  }

  CliEnvelope<T> parseCli<T>(T Function(Map<String, dynamic>) fromJson) {
    final decoded = _bodyAsJsonMap(_body);
    if (decoded.keys.contains('body')) {
      return CliEnvelope<T>(body: fromJson(_mapFromJson(decoded['body'])));
    }
    if (decoded.keys.contains('success')) {
      return CliEnvelope<T>(
          success: CliMessage.fromJson(_mapFromJson(decoded['success'])));
    }
    if (decoded.keys.contains('error')) {
      return CliEnvelope<T>(
          error: CliError.fromJson(_mapFromJson(decoded['error'])));
    }
    if (decoded.keys.contains('message')) {
      final message = decoded['message'] as String? ?? '';
      if (status >= 400) {
        return CliEnvelope<T>(error: CliError(message: message));
      }
      return CliEnvelope<T>(success: CliMessage(message: message));
    }
    if (decoded.isEmpty) {
      if (status >= 400) {
        return CliEnvelope<T>(error: CliError(message: 'Empty response'));
      }
      return CliEnvelope<T>(success: CliMessage(message: ''));
    }
    throw UnexpectedHttpResponseException(_body);
  }

  PubEnvelope<T> parsePub<T>(T Function(Map<String, dynamic>) fromJson) {
    final decoded = _bodyAsJsonMap(_body);
    if (status == 200) {
      return PubEnvelope<T>(body: fromJson(decoded));
    }
    if (decoded.keys.contains('error')) {
      return PubEnvelope<T>(
          error: PubError.fromJson(_mapFromJson(decoded['error'])));
    }
    return PubEnvelope<T>(error: PubError(message: 'Unknown error'));
  }

  @override
  String toString() => 'status: $status, body: $_body';
}

/// Takes the body, assumes its a json string and
/// converts it to a map.
Map<String, dynamic> _bodyAsJsonMap(String body) {
  try {
    return jsonDecode(body) as Map<String, dynamic>;
  } on Exception {
    print('Server response follows...');
    print('');
    print(body);
    print(red('Bad response from server, please try again later.'));

    rethrow;
  }
}

Map<String, dynamic> _mapFromJson(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map<String, Object?>) {
    return Map<String, dynamic>.from(value);
  }
  return <String, dynamic>{};
}

String toHex(List<int> bytes) {
  final hex = StringBuffer();
  for (final val in bytes) {
    hex
      ..write(val.toRadixString(16).padLeft(2, '0'))
      ..write(' ');
  }
  return hex.toString();
}

String toAscii(List<int> bytes) {
  final ascii = StringBuffer();
  for (final val in bytes) {
    final char = isPrintable(val) ? String.fromCharCode(val) : ' ';

    ascii.write(char);
  }

  return ascii.toString();
}

bool isPrintable(int codeUnit) {
  var printable = true;

  if (codeUnit < 33) {
    printable = false;
  }
  if (codeUnit >= 127) {
    printable = false;
  }

  return printable;
}
