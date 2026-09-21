import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:graphql/client.dart';
import 'package:http/http.dart' as http;

import 'gateway_status.dart';

bool isPermissionDenied(Object error) {
  bool forbidden(String message) {
    final firstLine = message.split('\n').first.trim();
    return firstLine.replaceFirst(
          RegExp(r'^Exception while fetching data \([^)]*\)\s*:\s*'),
          '',
        ) ==
        'Forbidden';
  }

  if (error is OperationException) {
    return error.graphqlErrors.any((entry) => forbidden(entry.message));
  }
  final message = error.toString().trim();
  return message.isNotEmpty && message.split(', ').every(forbidden);
}

bool isAuthenticationRequired(Object error) {
  if (error is OperationException) {
    if (error.graphqlErrors.any(
      (entry) =>
          entry.extensions?['http'] is Map &&
              (entry.extensions!['http'] as Map)['status'] == 401 ||
          entry.message.toLowerCase().contains('unauthor'),
    )) {
      return true;
    }
    final link = error.linkException;
    return link != null && isAuthenticationRequired(link);
  }
  if (error is HttpLinkServerException) {
    return error.response.statusCode == 401;
  }
  if (error is ResponseFormatException) {
    final original = error.originalException;
    return original != null && isAuthenticationRequired(original);
  }
  return error is ServerNotJsonException && error.statusCode == 401;
}

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
        isGatewayStatus(link.response.statusCode)) {
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
    (e is ServerNotJsonException && isGatewayStatus(e.statusCode));
