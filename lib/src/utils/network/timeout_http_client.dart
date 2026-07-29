import 'dart:async';

import 'package:http/http.dart' as http;

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
    http.Client? inner,
  }) : _inner = inner ?? createFastConnectClient(kConnectionEstablishTimeout);

  /// The timeout duration for each request.
  final Duration timeout;
  final int retries;
  final Duration retryDelay;

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    int attempt = 0;
    http.BaseRequest current = request;

    while (true) {
      try {
        return await _inner.send(current).timeout(timeout);
      } on TimeoutException {
        if (attempt >= retries) rethrow;
        // Streamed/multipart bodies are single-use and can't be safely retried.
        final retryClone = _cloneRequest(request);
        if (retryClone == null) rethrow;
        attempt++;
        await Future.delayed(retryDelay);
        current = retryClone;
      }
    }
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }

  // Clones a plain [http.Request] for retry; null for streamed/multipart bodies.
  http.BaseRequest? _cloneRequest(http.BaseRequest original) {
    if (original is http.Request) {
      final clone = http.Request(original.method, original.url)
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
