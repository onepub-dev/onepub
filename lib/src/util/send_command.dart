import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dcli/dcli.dart';

import '../exceptions.dart';
import '../onepub_settings.dart';

/// Takes the body, assumes its a json string and
/// converts it to a map.
Map<String, dynamic> bodyAsJsonMap(String body) =>
    jsonDecode(body) as Map<String, dynamic>;

enum Method { get, post }

Future<EndpointResponse> sendCommand(
    {required String command,
    bool authorised = true,
    Map<String, String> headers = const <String, String>{},
    String? body,
    Method method = Method.get}) async {
  final resolvedEndpoint = OnepubSettings().resolveApiEndPoint(command);

  verbose(() => 'Sending command to $resolvedEndpoint');

  final uri = Uri.parse(resolvedEndpoint);

  try {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);

    /// allow self signed/staged certs in dev
    if (OnepubSettings().allowBadCertificates) {
      client.badCertificateCallback = (cert, host, port) => true;
    }

    final response =
        await _startRequest(client, method, uri, headers, body, authorised);

    return await _processData(client, response);
  } on SocketException catch (e) {
    throw FetchException.fromException(e);
  } finally {}
}

Future<HttpClientResponse> _startRequest(HttpClient client, Method method,
    Uri uri, Map<String, String> headers, String? body, bool authorised) async {
  final _headers = <String, String>{}..addAll(headers);

  if (authorised) {
    if (!isLoggedIn) {
      throw ExitException(exitCode: 1, message: '''
You must be logged in to run this command.
run: 
  onepub login
  ''');
    }
    final onepubToken = OnepubSettings().onepubToken;

    _headers.addAll({'authorization': onepubToken});
  }

  final HttpClientRequest request;
  switch (method) {
    case Method.get:
      request = await client.getUrl(uri);
      _addHeaders(_headers, request);
      break;
    case Method.post:
      request = await client.postUrl(uri);
      _addHeaders(_headers, request);
      if (body != null) {
        request.write(body);
      }
      break;
  }

  final response = await request.close();

  final responseHeaders = <String, List<String>>{};
  response.headers.forEach((name, values) => responseHeaders[name] = values);
  return response;
}

/// add custom headers to the request object.
void _addHeaders(Map<String, String> _headers, HttpClientRequest request) {
  if (_headers.isNotEmpty) {
    for (final header in _headers.entries) {
      request.headers.add(header.key, header.value, preserveHeaderCase: true);
    }
  }
}

Future<EndpointResponse> _processData(
  HttpClient client,
  HttpClientResponse response,
) async {
  final completer = Completer<EndpointResponse>();

  final body = StringBuffer();

  // var lengthReceived = 0;
  // final contentLength = response.contentLength;
  // we have a response.

  late StreamSubscription<List<int>> subscription;
  subscription = response.listen(
    (newBytes) async {
      /// if we don't pause we get overlapping calls from listen
      /// which causes the [writeFrom] to fail as you can't
      /// do overlapping io.
      subscription.pause();

      /// we have new data to save.
      body.write(utf8.decode(newBytes));

      // lengthReceived += newBytes.length;

      subscription.resume();
    },
    onDone: () async {
      /// down load is complete
      await subscription.cancel();
      client.close();

      completer.complete(EndpointResponse(response.statusCode, body));
    },
    // ignore: avoid_types_on_closure_parameters
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

class EndpointResponse {
  EndpointResponse(this.status, StringBuffer body) : _body = body.toString();

  int status;
  final String _body;

  var _success = false;
  var _parsed = false;
  late final Map<String, Object?> _data;

  /// the result json data as a map.
  Map<String, Object?> get data {
    _parse();
    return _data;
  }

  bool get success => _success;

  /// We expect a response of the form:
  /// {"success":{"message":"Onepub.dev status normal."}}
  /// or
  /// {"error":{"bad things."}}

  void _parse() {
    if (!_parsed) {
      final decodedResponse = bodyAsJsonMap(_body);

      if (decodedResponse.keys.contains('success')) {
        _data = decodedResponse['success'] as Map<String, Object?>;
        _success = true;
      } else if (decodedResponse.keys.contains('error')) {
        _data = decodedResponse['error'] as Map<String, Object?>;
        _success = false;
      } else {
        throw UnexpectedHttpResponseException(message: _body);
      }
      _parsed = true;
    }
  }

  /// Takes the body, assumes its a json string and
  /// converts it to a map.
  Map<String, dynamic> bodyAsJsonMap(String body) =>
      jsonDecode(body) as Map<String, dynamic>;

  @override
  String toString() => 'status: $status, data: ${data.toString()}';
}
