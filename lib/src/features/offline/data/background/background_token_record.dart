// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import '../../../../utils/crash/diagnostics.dart';
import '../../../auth/data/jwt_utils.dart';
import 'record_seal.dart';

typedef RefreshResult = ({String access, String refresh});

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
  // Check credential endpoint before writeback after a server switch.
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

  /// Custom headers accompany every worker request; workers have no Riverpod access.
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

  // Seal all secrets, including custom-header tokens: these records live outside secure storage.
  Map<String, Object?> toJson() => {
    'gen': gen,
    'authType': authType,
    'endpoint': endpoint,
    'identityEpoch': identityEpoch,
    'catalogServerId': catalogServerId,
    'notificationSessionId': notificationSessionId,
    // No key means no secrets; never persist plaintext credentials.
    if (RecordSeal.ready)
      'sealed': RecordSeal.seal({
        'originalRefreshToken': originalRefreshToken,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'password': password,
        'basicCredential': basicCredential,
        'simpleCookie': simpleCookie,
        'extraHeaders': extraHeaders,
      }),
  };

  /// Accepts legacy plaintext records; unreadable sealed secrets authenticate as nobody.
  factory BackgroundTokenRecord.fromJson(Map<String, Object?> j) {
    final sealed = j['sealed'];
    final secrets = sealed is String
        ? RecordSeal.open(sealed) ?? const <String, Object?>{}
        : j;
    return BackgroundTokenRecord(
      gen: j['gen'] as int,
      authType: j['authType'] as String,
      endpoint: j['endpoint'] as String?,
      identityEpoch: j['identityEpoch'] as int?,
      catalogServerId: j['catalogServerId'] as String?,
      originalRefreshToken: secrets['originalRefreshToken'] as String?,
      notificationSessionId: j['notificationSessionId'] as String?,
      accessToken: secrets['accessToken'] as String?,
      refreshToken: secrets['refreshToken'] as String?,
      password: secrets['password'] as String?,
      basicCredential: secrets['basicCredential'] as String?,
      simpleCookie: secrets['simpleCookie'] as String?,
      extraHeaders:
          (secrets['extraHeaders'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(), v.toString()),
          ) ??
          const {},
    );
  }
}

/// Merges custom headers without overriding the app's auth headers.
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

/// Suwayomi can return HTTP 200 with GraphQL extensions.http.status 401 after verifyJwt falls back to Visitor.
/// Treat in-band authorization errors as 401 so background token refresh runs.
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

/// Distinguishes transient refresh outages from explicit credential rejection.
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

  /// Describes the latest null resolveAfter401 result; outages remain retryable.
  bool lastRefreshTransient = false;

  static const Duration refreshLead = Duration(seconds: 60);

  // Reuse a recent failed early refresh for the following 401 on the same token.
  static const Duration _failedRefreshReuse = Duration(seconds: 15);

  BackgroundTokenRecord? _latest;
  Future<BackgroundTokenRecord>? _refreshAhead;
  String? _failedFor;
  DateTime? _failedAt;

  BackgroundTokenRecord? get latest => _latest;

  /// Refreshes near-expiry ui_login tokens; concurrent callers share one attempt.
  /// Returns [record] on failure so the request can follow the normal 401 path.
  Future<BackgroundTokenRecord> refreshIfDue(
    BackgroundTokenRecord record, {
    DateTime? now,
  }) {
    if (record.authType != 'uiLogin' || record.refreshToken == null) {
      return Future.value(record);
    }
    final token = record.accessToken;
    final exp = token == null || token.isEmpty ? null : decodeJwtExp(token);
    // Opaque tokens have no readable expiry; refresh through the 401 path.
    if (exp == null && token != null && token.isNotEmpty) {
      return Future.value(record);
    }
    final left = exp?.difference(now ?? DateTime.now().toUtc());
    if (left != null && left > refreshLead) return Future.value(record);
    return _refreshAhead ??= () async {
      try {
        final fresh = await _resolve(token ?? '', rejected: false);
        _log(
          'refresh-ahead expIn=${left?.inSeconds ?? 'none'}s '
          '${fresh == null ? 'failed transient=$lastRefreshTransient' : 'ok'}',
        );
        if (fresh == null) {
          _failedFor = token ?? '';
          _failedAt = DateTime.now();
          return record;
        }
        return await readCurrent() ?? record;
      } finally {
        _refreshAhead = null;
      }
    }();
  }

  /// Null on failure; inspect lastRefreshTransient before treating auth as invalid.
  Future<String?> resolveAfter401(String tokenThat401d) {
    final failedAt = _failedAt;
    if (tokenThat401d == _failedFor &&
        failedAt != null &&
        DateTime.now().difference(failedAt) < _failedRefreshReuse) {
      _log('auth-rejected after-failed-refresh-ahead');
      return Future.value(null);
    }
    return _resolve(tokenThat401d);
  }

  Future<String?> _resolve(String tokenThat401d, {bool rejected = true}) async {
    lastRefreshTransient = false;
    final current = await _read();
    if (rejected) _log('auth-rejected gen=${current.gen}');
    if (expectedIdentity != null && !current.sameIdentity(expectedIdentity!)) {
      _log('identity-changed-before-refresh gen=${current.gen}');
      return null;
    }
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
    final next = current.copyWith(
      gen: current.gen + 1,
      accessToken: tokens.access,
      refreshToken: tokens.refresh,
    );
    await write(next);
    _latest = next;
    _failedFor = null;
    _log('refreshed gen=${next.gen}');
    return tokens.access;
  }

  static void _log(String event) => recordDiagnostic(
    '[${DateTime.now().toIso8601String()}] token-broker: $event\n',
  );
}
