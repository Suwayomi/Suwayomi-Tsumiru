import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:http/http.dart' as http;

/// The server answered with a body that isn't JSON — a proxy/gateway error
/// page, an HTML 500, etc. Carries the status so the UI can say "server error"
/// instead of a raw "Unexpected character (at offset 0)".
class ServerNotJsonException implements Exception {
  const ServerNotJsonException(this.statusCode, this.snippet);
  final int statusCode;
  final String snippet;
  @override
  String toString() => 'Server returned a non-JSON response (HTTP $statusCode)';
}

/// HttpLink response decoder that turns a non-JSON body into a clear typed
/// error instead of the default parser FormatException.
Map<String, dynamic>? tsumiruHttpResponseDecoder(http.Response response) {
  final body = utf8.decode(response.bodyBytes, allowMalformed: true);
  try {
    final decoded = json.decode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    throw const FormatException('not a JSON object');
  } on FormatException {
    final oneLine = body.trim().replaceAll(RegExp(r'\s+'), ' ');
    throw ServerNotJsonException(
      response.statusCode,
      oneLine.length > 200 ? '${oneLine.substring(0, 200)}…' : oneLine,
    );
  }
}

/// True only when the request never reached the Suwayomi server — the one
/// case where falling back to the offline cache is right. The server itself
/// answering with an error (500/parse/auth) is not this, but a reverse proxy
/// answering FOR an unreachable upstream (502/503/504) is: the user's server
/// is down, only the middleman is talking.
bool isConnectionError(Object error) {
  if (error is OperationException) {
    final link = error.linkException;
    if (link is HttpLinkServerException &&
        _isGatewayStatus(link.response.statusCode)) {
      // A gateway status is the middleman speaking for a dead origin even
      // when its body happens to parse (some balancers emit JSON errors).
      return true;
    }
    if (link is ServerException && link.parsedResponse == null) {
      return _isSocketLike(link.originalException);
    }
    // A response-decoder throw (our ServerNotJsonException) arrives wrapped
    // in the PARSER exception, a sibling of ServerException — not inside it.
    if (link is ResponseFormatException) {
      return _isSocketLike(link.originalException);
    }
    return false;
  }
  return _isSocketLike(error);
}

bool _isSocketLike(Object? e) =>
    e is SocketException ||
    e is TimeoutException ||
    e is HandshakeException ||
    e is http.ClientException ||
    (e is ServerNotJsonException && _isGatewayStatus(e.statusCode));

// A proxy answering for a dead origin: 502/503/504, plus Cloudflare's
// origin-down codes. 520/525/526 stay surfaced — the origin is alive but
// misbehaving there, which the user must see to fix.
bool _isGatewayStatus(int status) =>
    status == 502 || status == 503 || status == 504 ||
    (status >= 521 && status <= 524);
