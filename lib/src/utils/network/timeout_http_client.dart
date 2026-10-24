import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../crash/diagnostics.dart';

import 'fast_connect_client_stub.dart'
    if (dart.library.io) 'fast_connect_client_io.dart';

/// Connection establishment limit; slow responses still get the full request timeout.
const kConnectionEstablishTimeout = Duration(seconds: 8);

class TimeoutHttpClient extends http.BaseClient {
  TimeoutHttpClient(
    this.timeout, {
    this.retries = 0,
    this.retryDelay = const Duration(seconds: 1),
    this.onConnectionFailure,
    this.isCurrentSession,
    this.retryHeaders,
    http.Client? inner,
  }) : _inner = inner ?? createFastConnectClient(kConnectionEstablishTimeout);

  final Duration timeout;
  final int retries;
  final Duration retryDelay;

  /// Retry the returned endpoint once, even with retries disabled; return null for unsafe replays.
  final Future<Uri?> Function(http.BaseRequest request)? onConnectionFailure;

  final bool Function()? isCurrentSession;

  /// Refresh retry headers below the auth link; throwing abandons the retry with the original failure.
  final Future<Map<String, String>> Function(Map<String, String> headers)?
  retryHeaders;

  final http.Client _inner;

  void _checkSession() {
    if (isCurrentSession?.call() == false) {
      throw StateError('Authentication session changed');
    }
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    int attempt = 0;
    http.BaseRequest current = request;
    var usedFailover = false;
    // A timed-out GraphQL mutation may already be applied; never replay it.
    final isMutation = _isMutationRequest(request);

    Future<http.BaseRequest?> retryAfterFailure(Object error) async {
      _checkSession();
      if (isMutation) return null;

      Uri? replacement;
      if (!usedFailover && onConnectionFailure != null) {
        _checkSession();
        replacement = await onConnectionFailure!(current);
        _checkSession();
        usedFailover = replacement != null && replacement != current.url;
      }

      if (!usedFailover && attempt >= retries) return null;
      // Streamed/multipart bodies are single-use and can't be safely retried.
      final retryClone = _cloneRequest(current, url: replacement);
      if (retryClone == null) return null;
      attempt++;
      recordDiagnostic(
        '[${DateTime.now().toIso8601String()}] http-retry: '
        'attempt=$attempt failover=${replacement != null} '
        'cause=${error.runtimeType}\n',
      );
      if (replacement == null) await Future.delayed(retryDelay);
      if (retryHeaders != null) {
        try {
          final headers = await retryHeaders!(Map.of(retryClone.headers));
          retryClone.headers
            ..clear()
            ..addAll(headers);
        } catch (_) {
          return null;
        }
        _checkSession();
      }
      return retryClone;
    }

    while (true) {
      try {
        _checkSession();
        return await _inner.send(current).timeout(timeout);
      } on TimeoutException catch (e) {
        final retry = await retryAfterFailure(e);
        if (retry == null) rethrow;
        current = retry;
      } on http.ClientException catch (e) {
        final retry = await retryAfterFailure(e);
        if (retry == null) rethrow;
        current = retry;
      }
    }
  }

  /// Only a parseable GraphQL mutation is unsafe; other request bodies are treated as retryable.
  bool _isMutationRequest(http.BaseRequest request) {
    if (request is! http.Request) return false;
    try {
      final decoded = jsonDecode(request.body);
      if (decoded is! Map) return false;
      final query = decoded['query'];
      if (query is! String) return false;
      return query.trimLeft().startsWith('mutation');
    } catch (_) {
      return false;
    }
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }

  http.BaseRequest? _cloneRequest(http.BaseRequest original, {Uri? url}) {
    if (original is http.Request) {
      final clone = http.Request(original.method, url ?? original.url)
        ..headers.addAll(original.headers)
        ..followRedirects = original.followRedirects
        ..persistentConnection = original.persistentConnection;

      if (original.bodyBytes.isNotEmpty) {
        clone.bodyBytes = original.bodyBytes;
      }
      return clone;
    }
    return null;
  }
}
