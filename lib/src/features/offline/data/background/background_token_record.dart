// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import '../../../../utils/crash/diagnostics.dart';

typedef RefreshResult = ({String access, String refresh});

/// Logs one background refresh-call outcome that would otherwise leave no
/// trace. `source` names the worker (`notify`, `download`); the error keeps
/// its type, since `package:http` wraps a socket failure in a
/// `ClientException` that a bare `on SocketException` doesn't catch.
void logBackgroundRefresh(String source, String event, [Object? error]) {
  final cause = error == null
      ? ''
      : ' cause=${error.runtimeType}: '
            '${error.toString().split('\n').first.trim()}';
  recordDiagnostic(
    '[${DateTime.now().toIso8601String()}] offline-refresh: '
    'source=$source $event$cause\n',
  );
}

class BackgroundTokenRecord {
  const BackgroundTokenRecord({
    required this.gen,
    required this.authType,
    this.endpoint,
    this.identityEpoch,
    this.catalogServerId,
    this.originalRefreshToken,
    this.notificationSessionId,
    this.accessToken,
    this.refreshToken,
    this.password,
    this.basicCredential,
    this.simpleCookie,
    this.extraHeaders = const {},
  });

  final int gen;
  final String authType; // basic | simpleLogin | uiLogin | none
  // Endpoint these creds belong to, checked before writeback after a switch.
  final String? endpoint;
  final int? identityEpoch;
  final String? catalogServerId;
  final String? originalRefreshToken;
  final String? notificationSessionId;
  final String? accessToken,
      refreshToken,
      password,
      basicCredential,
      simpleCookie;

  /// Generic custom headers (e.g. Cloudflare Zero Trust) snapshotted for the
  /// background isolate, which has no Riverpod access. Applied to every
  /// server request alongside the auth headers.
  final Map<String, String> extraHeaders;

  BackgroundTokenRecord copyWith({
    int? gen,
    String? accessToken,
    String? refreshToken,
    String? notificationSessionId,
  }) => BackgroundTokenRecord(
    gen: gen ?? this.gen,
    authType: authType,
    endpoint: endpoint,
    identityEpoch: identityEpoch,
    catalogServerId: catalogServerId,
    originalRefreshToken: originalRefreshToken,
    notificationSessionId: notificationSessionId ?? this.notificationSessionId,
    accessToken: accessToken ?? this.accessToken,
    refreshToken: refreshToken ?? this.refreshToken,
    password: password,
    basicCredential: basicCredential,
    simpleCookie: simpleCookie,
    extraHeaders: extraHeaders,
  );

  bool sameIdentity(BackgroundTokenRecord other) =>
      authType == other.authType &&
      endpoint == other.endpoint &&
      identityEpoch == other.identityEpoch &&
      catalogServerId == other.catalogServerId &&
      originalRefreshToken == other.originalRefreshToken;

  Map<String, Object?> toJson() => {
    'gen': gen,
    'authType': authType,
    'endpoint': endpoint,
    'identityEpoch': identityEpoch,
    'catalogServerId': catalogServerId,
    'originalRefreshToken': originalRefreshToken,
    'notificationSessionId': notificationSessionId,
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'password': password,
    'basicCredential': basicCredential,
    'simpleCookie': simpleCookie,
    'extraHeaders': extraHeaders,
  };

  factory BackgroundTokenRecord.fromJson(Map<String, Object?> j) =>
      BackgroundTokenRecord(
        gen: j['gen'] as int,
        authType: j['authType'] as String,
        endpoint: j['endpoint'] as String?,
        identityEpoch: j['identityEpoch'] as int?,
        catalogServerId: j['catalogServerId'] as String?,
        originalRefreshToken: j['originalRefreshToken'] as String?,
        notificationSessionId: j['notificationSessionId'] as String?,
        accessToken: j['accessToken'] as String?,
        refreshToken: j['refreshToken'] as String?,
        password: j['password'] as String?,
        basicCredential: j['basicCredential'] as String?,
        simpleCookie: j['simpleCookie'] as String?,
        extraHeaders:
            (j['extraHeaders'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), v.toString()),
            ) ??
            const {},
      );
}

/// Merge isolate-side custom headers into [headers] without clobbering the
/// app's own auth headers. Shared by the background download / notification
/// workers (no Riverpod there).
Map<String, String> applyIsolateCustomHeaders(
  Map<String, String> headers,
  Map<String, String> extra,
) {
  for (final entry in extra.entries) {
    final lower = entry.key.toLowerCase();
    if (lower == 'authorization' || lower == 'cookie') continue;
    headers[entry.key] = entry.value;
  }
  return headers;
}

/// Suwayomi reports an expired/invalid access token as HTTP **200** with a
/// GraphQL error carrying `extensions.http.status == 401` (or an "unauthorized"
/// message), NOT an HTTP 401 — `verifyJwt` downgrades a bad token to a Visitor
/// and the `@requireAuth` field errors in-band. Every background GraphQL path
/// must treat this like a 401 so the broker refresh fires; the foreground
/// `SuwayomiAuthLink` already does. Without it, once the server's short
/// (default 5-minute) access token expires, every background run fails silently
/// and never refreshes. Shared by the notification client and the catch-up
/// fetch path so both detect it identically.
bool isGraphqlAuthError(Object? errors) {
  if (errors is! List) return false;
  for (final err in errors) {
    if (err is! Map) continue;
    final ext = err['extensions'];
    final http = ext is Map ? ext['http'] : null;
    if (http is Map && http['status'] == 401) return true;
    final message = err['message'];
    if (message is String && message.toLowerCase().contains('unauthor')) {
      return true;
    }
  }
  return false;
}

/// Outcome of one refresh attempt: the new tokens on success, or a failure
/// that distinguishes "the refresh call itself couldn't reach the server"
/// (transient — retry later, auth may still be fine) from "the server
/// responded and rejected the refresh token" (auth is genuinely dead).
typedef RefreshAttempt = ({RefreshResult? tokens, bool transient});

class TokenBroker {
  TokenBroker({
    required Future<BackgroundTokenRecord> Function() read,
    required this.write,
    required this.refreshFn,
    this.expectedIdentity,
  }) : _read = read;
  final BackgroundTokenRecord? expectedIdentity;
  final Future<BackgroundTokenRecord> Function() _read;
  final Future<void> Function(BackgroundTokenRecord) write;
  final Future<RefreshAttempt> Function(String refreshToken) refreshFn;

  Future<BackgroundTokenRecord?> readCurrent() async {
    final current = await _read();
    return expectedIdentity == null || current.sameIdentity(expectedIdentity!)
        ? current
        : null;
  }

  /// Set by the most recent failed [resolveAfter401] — only meaningful right
  /// after it returns null. Without this, a caller treats a refresh that
  /// merely couldn't reach the server (e.g. right after the device
  /// reconnects, before the network has actually settled) the same as a
  /// refresh token the server explicitly rejected, and gives up on the
  /// chapter permanently instead of retrying once the network is real.
  bool lastRefreshTransient = false;

  /// Returns a usable access token to retry with, or null if auth is dead.
  Future<String?> resolveAfter401(String tokenThat401d) async {
    lastRefreshTransient = false;
    final current = await _read();
    _log('auth-rejected gen=${current.gen}');
    if (expectedIdentity != null && !current.sameIdentity(expectedIdentity!)) {
      _log('identity-changed-before-refresh gen=${current.gen}');
      return null;
    }
    // Someone already refreshed to a different access token — use it, no refresh.
    if (current.accessToken != null && current.accessToken != tokenThat401d) {
      _log('reused-newer-token gen=${current.gen}');
      return current.accessToken;
    }
    final rt = current.refreshToken;
    if (rt == null) {
      lastRefreshTransient = false;
      _log('no-refresh-token gen=${current.gen}');
      return null;
    }
    final attempt = await refreshFn(rt);
    if (expectedIdentity != null &&
        !(await _read()).sameIdentity(expectedIdentity!)) {
      _log('identity-changed-during-refresh gen=${current.gen}');
      return null;
    }
    final tokens = attempt.tokens;
    if (tokens == null) {
      lastRefreshTransient = attempt.transient;
      return null;
    }
    await write(
      current.copyWith(
        gen: current.gen + 1,
        accessToken: tokens.access,
        refreshToken: tokens.refresh,
      ),
    );
    _log('refreshed gen=${current.gen + 1}');
    return tokens.access;
  }

  /// Every background 401 and how it ended: a refresh, a reused newer token, or
  /// why none happened. The callers log a null result only as
  /// `refresh-failed transient=…`, which can't tell an identity mismatch or a
  /// missing refresh token from a real rejection; and a successful refresh left
  /// no trace, so a healthy worker looked the same as one never challenged.
  static void _log(String event) => recordDiagnostic(
        '[${DateTime.now().toIso8601String()}] token-broker: $event\n',
      );
}
