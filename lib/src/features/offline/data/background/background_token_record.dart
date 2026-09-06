// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

typedef RefreshResult = ({String access, String refresh});

class BackgroundTokenRecord {
  const BackgroundTokenRecord({
    required this.gen,
    required this.authType,
    this.endpoint,
    this.accessToken,
    this.refreshToken,
    this.password,
    this.basicCredential,
    this.simpleCookie,
  });

  final int gen;
  final String authType; // basic | simpleLogin | uiLogin | none
  // Endpoint these creds belong to, checked before writeback after a switch.
  final String? endpoint;
  final String? accessToken, refreshToken, password, basicCredential, simpleCookie;

  BackgroundTokenRecord copyWith({int? gen, String? accessToken, String? refreshToken}) =>
      BackgroundTokenRecord(
        gen: gen ?? this.gen,
        authType: authType,
        endpoint: endpoint,
        accessToken: accessToken ?? this.accessToken,
        refreshToken: refreshToken ?? this.refreshToken,
        password: password,
        basicCredential: basicCredential,
        simpleCookie: simpleCookie,
      );

  Map<String, Object?> toJson() => {
        'gen': gen, 'authType': authType, 'endpoint': endpoint,
        'accessToken': accessToken, 'refreshToken': refreshToken,
        'password': password, 'basicCredential': basicCredential,
        'simpleCookie': simpleCookie,
      };

  factory BackgroundTokenRecord.fromJson(Map<String, Object?> j) =>
      BackgroundTokenRecord(
        gen: j['gen'] as int,
        authType: j['authType'] as String,
        endpoint: j['endpoint'] as String?,
        accessToken: j['accessToken'] as String?,
        refreshToken: j['refreshToken'] as String?,
        password: j['password'] as String?,
        basicCredential: j['basicCredential'] as String?,
        simpleCookie: j['simpleCookie'] as String?,
      );
}

/// Outcome of one refresh attempt: the new tokens on success, or a failure
/// that distinguishes "the refresh call itself couldn't reach the server"
/// (transient — retry later, auth may still be fine) from "the server
/// responded and rejected the refresh token" (auth is genuinely dead).
typedef RefreshAttempt = ({RefreshResult? tokens, bool transient});

/// Coordinates token refresh across the main and worker isolates against ONE
/// gen-versioned record, so a rotating refresh token is never lost-updated by two
/// holders. Pure logic: storage + the actual refresh network call are injected.
class TokenBroker {
  TokenBroker({required this.read, required this.write, required this.refreshFn});
  final Future<BackgroundTokenRecord> Function() read;
  final Future<void> Function(BackgroundTokenRecord) write;
  final Future<RefreshAttempt> Function(String refreshToken) refreshFn;

  /// Set by the most recent failed [resolveAfter401] — only meaningful right
  /// after it returns null. Without this, a caller treats a refresh that
  /// merely couldn't reach the server (e.g. right after the device
  /// reconnects, before the network has actually settled) the same as a
  /// refresh token the server explicitly rejected, and gives up on the
  /// chapter permanently instead of retrying once the network is real.
  bool lastRefreshTransient = false;

  /// Returns a usable access token to retry with, or null if auth is dead.
  Future<String?> resolveAfter401(String tokenThat401d) async {
    final current = await read();
    // Someone already refreshed to a different access token — use it, no refresh.
    if (current.accessToken != null && current.accessToken != tokenThat401d) {
      return current.accessToken;
    }
    final rt = current.refreshToken;
    if (rt == null) {
      lastRefreshTransient = false;
      return null;
    }
    final attempt = await refreshFn(rt);
    final tokens = attempt.tokens;
    if (tokens == null) {
      lastRefreshTransient = attempt.transient;
      return null;
    }
    await write(current.copyWith(
        gen: current.gen + 1, accessToken: tokens.access, refreshToken: tokens.refresh));
    return tokens.access;
  }
}
