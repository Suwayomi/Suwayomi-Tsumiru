import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../crash/diagnostics.dart';

import 'fast_connect_client_stub.dart'
    if (dart.library.io) 'fast_connect_client_io.dart';

/// How long a TCP/TLS connection may take to establish. Distinct from the
/// request [TimeoutHttpClient.timeout]: a slow RESPONSE deserves the full
/// window (the server may be building a big payload), but a connection that
/// hasn't even opened in this long is dead and should fail now — not after the
/// full window times all its retries.
const kConnectionEstablishTimeout = Duration(seconds: 8);

/// An [http.BaseClient] that applies a timeout to every request.
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

  /// The timeout duration for each request.
  final Duration timeout;
  final int retries;
  final Duration retryDelay;

  /// Selects an alternate endpoint after a connection failure. The returned
  /// URI is retried once immediately, even when ordinary timeout retries are
  /// disabled. Callers must return null for operations that are unsafe to
  /// replay.
  final Future<Uri?> Function(http.BaseRequest request)? onConnectionFailure;

  final bool Function()? isCurrentSession;

  /// Re-derives a retry's headers from the request's. Retries are replayed
  /// here, below the auth link, so a retry after a long stall (the app frozen
  /// mid-request) would otherwise resend the access token the request started
  /// with, long expired by then. Throwing abandons the retry and surfaces the
  /// original failure.
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
    // A GraphQL mutation isn't idempotent — a timeout doesn't mean the server
    // didn't already apply it, so retrying can silently double an effect
    // (re-enqueue a download, re-create a category, ...). This client is only
    // ever used for the GraphQL HttpLink, so its body is always the standard
    // `{"query": "...", ...}` shape when it parses as one.
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

  /// True only when [request] is confidently identified as a GraphQL
  /// mutation (a parseable `{"query": "mutation ..."}` body). Anything that
  /// doesn't parse that way — a plain query, an anonymous/shorthand query, a
  /// non-GraphQL body, no body at all — is treated as safe to retry, same as
  /// before this check existed.
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

  // Clones a plain [http.Request] for retry; null for streamed/multipart bodies.
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
