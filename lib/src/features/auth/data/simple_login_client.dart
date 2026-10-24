// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:http/http.dart' as http;

import '../../onboarding/data/server_resolver.dart' show authProbeAuthorized;

import 'simple_login_session_client_io.dart'
    if (dart.library.js_interop) 'simple_login_session_client_web.dart';

/// Nonempty session sentinel for browsers, which own cookies and forbid setting Cookie headers.
const kBrowserManagedSimpleSession = 'browser-managed-session';

/// Suwayomi signals rejected credentials with HTTP 200 and the login HTML.
class SimpleLoginAuthFailure implements Exception {
  const SimpleLoginAuthFailure();
  @override
  String toString() => 'SimpleLoginAuthFailure: invalid username/password';
}

/// Response is neither a 303 with cookie nor a 200 login-form rejection.
class SimpleLoginShapeFailure implements Exception {
  const SimpleLoginShapeFailure(this.message);
  final String message;
  @override
  String toString() => 'SimpleLoginShapeFailure: $message';
}

class SimpleLoginSessionFailure extends SimpleLoginShapeFailure {
  const SimpleLoginSessionFailure()
    : super('The server did not confirm the browser session');
}

class SimpleLoginClient {
  SimpleLoginClient({
    http.Client? httpClient,
    bool? browserSession,
    this.timeout = const Duration(seconds: 30),
  }) : _http = httpClient ?? makeSimpleLoginClient(timeout),
       _browserSession = browserSession ?? browserManagesSession;

  final http.Client _http;
  final Duration timeout;

  void close() => _http.close();

  final bool _browserSession;

  /// Returns the session cookie, or the browser-managed sentinel on web.
  /// Throws [SimpleLoginAuthFailure] for rejection, [SimpleLoginShapeFailure] for unexpected responses.
  Future<String> login({
    required String serverBaseUrl,
    required String username,
    required String password,
    Map<String, String>? extraHeaders,
  }) async {
    final request = http.Request('POST', Uri.parse('$serverBaseUrl/login.html'))
      ..bodyFields = {'user': username, 'pass': password}
      ..headers['Content-Type'] =
          'application/x-www-form-urlencoded; charset=utf-8'
      // Native must stop at the redirect to read Set-Cookie; browser fetch must follow it.
      ..followRedirects = _browserSession;
    if (extraHeaders != null && extraHeaders.isNotEmpty) {
      for (final entry in extraHeaders.entries) {
        final lower = entry.key.toLowerCase();
        if (lower == 'authorization' || lower == 'cookie') continue;
        request.headers[entry.key] = entry.value;
      }
    }
    final response = await http.Response.fromStream(
      await _http.send(request),
    ).timeout(timeout);

    if (_browserSession) {
      // Fetch forbids reading Set-Cookie; a protected request must verify the session.
      if (_looksLikeLoginForm(response.body)) {
        throw const SimpleLoginAuthFailure();
      }
      if (response.statusCode >= 400) {
        throw SimpleLoginShapeFailure(
          'unexpected status ${response.statusCode}',
        );
      }
      if (!await authProbeAuthorized(
        serverBaseUrl,
        client: _http,
        timeout: timeout,
        extraHeaders: extraHeaders,
      )) {
        throw const SimpleLoginSessionFailure();
      }
      return kBrowserManagedSimpleSession;
    }

    if (response.statusCode == 200) {
      throw const SimpleLoginAuthFailure();
    }
    if (response.statusCode != 303) {
      throw SimpleLoginShapeFailure('unexpected status ${response.statusCode}');
    }
    final setCookie = response.headers['set-cookie'];
    if (setCookie == null || setCookie.isEmpty) {
      throw const SimpleLoginShapeFailure(
        '303 response had no Set-Cookie header',
      );
    }
    final cookie = setCookie.split(';').first.trim();
    if (!await authProbeAuthorized(
      serverBaseUrl,
      client: _http,
      timeout: timeout,
      cookie: cookie,
      extraHeaders: extraHeaders,
    )) {
      throw const SimpleLoginSessionFailure();
    }
    return cookie;
  }

  static bool _looksLikeLoginForm(String body) =>
      body.contains('name="user"') && body.contains('name="pass"');
}
