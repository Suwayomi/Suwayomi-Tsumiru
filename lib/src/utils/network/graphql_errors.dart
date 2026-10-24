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

bool isAuthenticationRequired(Object error) => isSignInSessionEnded(error);

bool isSignInSessionEnded(Object error) {
  if (error is OperationException) {
    return error.graphqlErrors.any((entry) {
          final status = (entry.extensions?['http'] as Map?)?['status'];
          if (status != null) return status == 401;
          final message = entry.message
              .split('\n')
              .first
              .replaceFirst(
                RegExp(r'^Exception while fetching data \([^)]*\)\s*:\s*'),
                '',
              )
              .trim();
          return message == 'Unauthorized' || message == 'Visitor';
        }) ||
        (error.linkException != null &&
            isSignInSessionEnded(error.linkException!));
  }
  if (error is HttpLinkServerException) {
    return error.response.statusCode == 401;
  }
  if (error is LinkException && error.originalException != null) {
    return isSignInSessionEnded(error.originalException!);
  }
  if (error is ServerNotJsonException) {
    // Stable v2.4.2366 Jwt.kt:95–96 throws this plain-text HTTP 400.
    return error.statusCode == 401 ||
        (error.statusCode == 400 &&
            error.snippet.startsWith('Token intended for different audience'));
  }
  return false;
}

/// A Basic-auth server answers anonymous GraphQL with a readable 404 "Not Found".
bool isBasicGatedNotFound(Object error) {
  if (error is OperationException) {
    final link = error.linkException;
    return link != null && isBasicGatedNotFound(link);
  }
  if (error is ResponseFormatException) {
    final original = error.originalException;
    return original != null && isBasicGatedNotFound(original);
  }
  return error is ServerNotJsonException &&
      error.statusCode == 404 &&
      error.snippet.trim() == 'Not Found';
}

/// Non-JSON response retaining the HTTP status for user-facing errors.
class ServerNotJsonException implements Exception {
  const ServerNotJsonException(this.statusCode, this.snippet);
  final int statusCode;
  final String snippet;
  @override
  String toString() => 'Server returned a non-JSON response (HTTP $statusCode)';
}

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

/// Unreachable origin only: includes proxy gateway errors, excludes server parse/auth/500 errors.
bool isConnectionError(Object error) {
  if (error is OperationException) {
    final link = error.linkException;
    if (link is HttpLinkServerException &&
        isGatewayStatus(link.response.statusCode)) {
      // A gateway error still means unreachable origin when its body is valid JSON.
      return true;
    }
    if (link is ServerException && link.parsedResponse == null) {
      return _isSocketLike(link.originalException);
    }
    // Decoder errors arrive inside the parser exception, not ServerException.
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
