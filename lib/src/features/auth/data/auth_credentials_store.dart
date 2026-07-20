// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'jwt_utils.dart';
import 'secure_credentials_provider.dart';

part 'auth_credentials_store.g.dart';

/// Holds an access + refresh token pair for UI Login mode.
class UiLoginTokens {
  const UiLoginTokens({required this.accessToken, required this.refreshToken});
  final String accessToken;
  final String refreshToken;
}

/// In-memory snapshot of every credential the app holds. This is the
/// `state` of [AuthCredentialsStore] — synchronously readable via
/// `ref.watch(authCredentialsStoreProvider).value` so widgets like
/// `server_image` can authenticate on the first frame without an
/// `AsyncLoading` flash that would otherwise cache a 401.
///
/// All fields are nullable: any value the user hasn't set is simply `null`.
class AuthCredentialsState {
  const AuthCredentialsState({
    this.password,
    this.simpleLoginCookie,
    this.uiAccessToken,
    this.uiRefreshToken,
    this.uiAccessTokenExpiresAt,
  });

  const AuthCredentialsState.empty()
      : password = null,
        simpleLoginCookie = null,
        uiAccessToken = null,
        uiRefreshToken = null,
        uiAccessTokenExpiresAt = null;

  final String? password;
  final String? simpleLoginCookie;
  final String? uiAccessToken;
  final String? uiRefreshToken;

  /// Decoded `exp` claim from the current `uiAccessToken`, or `null` if
  /// no token is present or the token was malformed. Derived from the
  /// JWT — NOT persisted separately to secure storage — and recomputed
  /// every time `uiAccessToken` is set.
  final DateTime? uiAccessTokenExpiresAt;

  /// Convenience: `{'Authorization': 'Bearer <jwt>'}` or `null` when no
  /// access token is present. Used by `SuwayomiAuthLink.getHeaders`.
  Map<String, String>? get uiAuthorizationHeader =>
      (uiAccessToken == null || uiAccessToken!.isEmpty)
          ? null
          : {'Authorization': 'Bearer $uiAccessToken'};

  /// Convenience: `{'Cookie': '<cookie>'}` or `null`. Used by
  /// `SuwayomiAuthLink.getHeaders` and `server_image`.
  Map<String, String>? get simpleLoginCookieHeader =>
      (simpleLoginCookie == null || simpleLoginCookie!.isEmpty)
          ? null
          : {'Cookie': simpleLoginCookie!};

  AuthCredentialsState copyWith({
    String? password,
    bool clearPassword = false,
    String? simpleLoginCookie,
    bool clearSimpleLoginCookie = false,
    String? uiAccessToken,
    bool clearUiAccessToken = false,
    String? uiRefreshToken,
    bool clearUiRefreshToken = false,
    DateTime? uiAccessTokenExpiresAt,
    bool clearUiAccessTokenExpiresAt = false,
  }) {
    return AuthCredentialsState(
      password: clearPassword ? null : (password ?? this.password),
      simpleLoginCookie: clearSimpleLoginCookie
          ? null
          : (simpleLoginCookie ?? this.simpleLoginCookie),
      uiAccessToken: clearUiAccessToken
          ? null
          : (uiAccessToken ?? this.uiAccessToken),
      uiRefreshToken: clearUiRefreshToken
          ? null
          : (uiRefreshToken ?? this.uiRefreshToken),
      uiAccessTokenExpiresAt: clearUiAccessTokenExpiresAt
          ? null
          : (uiAccessTokenExpiresAt ?? this.uiAccessTokenExpiresAt),
    );
  }
}

/// Typed wrapper over `flutter_secure_storage` for auth credentials.
///
/// Storage key conventions (all in secure storage):
///   `auth.password`            — password for simpleLogin + uiLogin re-auth
///   `auth.simple.cookie`       — full Cookie header value (e.g.
///                                "JSESSIONID=abc123") for simpleLogin
///   `auth.ui.accessToken`      — current uiLogin access token (JWT)
///   `auth.ui.refreshToken`     — uiLogin refresh token (JWT)
///   `auth.basic.credentials`   — migrated `Basic <base64(user:pass)>` from
///                                legacy SharedPreferences (see Task 7a)
///
/// Username lives in SharedPreferences (via DBKeys.authUsername) since it's
/// not sensitive on its own.
///
/// **Reactivity:** This is an `AsyncNotifier`. `build()` loads every key from
/// secure storage exactly once at startup; mutators write through to
/// secure storage AND update `state`, so widgets watching the provider
/// rebuild immediately on token rotation / login / logout.
@Riverpod(keepAlive: true)
class AuthCredentialsStore extends _$AuthCredentialsStore {
  static const _kPasswordKey = 'auth.password';
  static const _kSimpleCookieKey = 'auth.simple.cookie';
  static const _kUiAccessKey = 'auth.ui.accessToken';
  static const _kUiRefreshKey = 'auth.ui.refreshToken';
  static const _kBasicCredentialsKey = 'auth.basic.credentials';

  @override
  Future<AuthCredentialsState> build() async {
    final storage = ref.read(secureStorageProvider);
    final results = await Future.wait([
      storage.read(key: _kPasswordKey),
      storage.read(key: _kSimpleCookieKey),
      storage.read(key: _kUiAccessKey),
      storage.read(key: _kUiRefreshKey),
    ]);
    return AuthCredentialsState(
      password: results[0],
      simpleLoginCookie: results[1],
      uiAccessToken: results[2],
      uiRefreshToken: results[3],
      uiAccessTokenExpiresAt:
          results[2] == null ? null : decodeJwtExp(results[2]!),
    );
  }

  /// Current snapshot, or `AuthCredentialsState.empty()` if `build()`
  /// hasn't completed yet. Used internally by mutators that need to
  /// apply `copyWith` even before the initial load finishes.
  AuthCredentialsState get _current =>
      state.value ?? const AuthCredentialsState.empty();

  // Bumped by [clearAllForServerSwitch]; a delayed write racing a switch
  // captures a stale epoch and discards itself instead of writing.
  int _serverEpoch = 0;
  int get serverEpoch => _serverEpoch;

  // ---------- Password ----------

  Future<void> savePassword(String password, {int? forEpoch}) async {
    if (forEpoch != null && forEpoch != _serverEpoch) return;
    final storage = ref.read(secureStorageProvider);
    await storage.write(key: _kPasswordKey, value: password);
    if (forEpoch != null && forEpoch != _serverEpoch) {
      await storage.delete(key: _kPasswordKey);
      return;
    }
    state = AsyncData(_current.copyWith(password: password));
  }

  Future<void> clearPassword() async {
    await ref.read(secureStorageProvider).delete(key: _kPasswordKey);
    state = AsyncData(_current.copyWith(clearPassword: true));
  }

  // ---------- Simple Login ----------

  Future<void> saveSimpleLoginCookie(String cookieValue, {int? forEpoch}) async {
    if (forEpoch != null && forEpoch != _serverEpoch) return;
    final storage = ref.read(secureStorageProvider);
    await storage.write(key: _kSimpleCookieKey, value: cookieValue);
    if (forEpoch != null && forEpoch != _serverEpoch) {
      await storage.delete(key: _kSimpleCookieKey);
      return;
    }
    state = AsyncData(_current.copyWith(simpleLoginCookie: cookieValue));
  }

  Future<void> clearSimpleLoginCookie() async {
    await ref.read(secureStorageProvider).delete(key: _kSimpleCookieKey);
    state = AsyncData(_current.copyWith(clearSimpleLoginCookie: true));
  }

  // ---------- UI Login ----------

  /// [forEpoch]: discards (or undoes) the write if a switch bumps [serverEpoch]
  /// before or during the storage write.
  Future<void> saveUiLoginTokens({
    required String accessToken,
    required String refreshToken,
    int? forEpoch,
  }) async {
    if (forEpoch != null && forEpoch != _serverEpoch) return;
    final storage = ref.read(secureStorageProvider);
    await storage.write(key: _kUiAccessKey, value: accessToken);
    await storage.write(key: _kUiRefreshKey, value: refreshToken);
    if (forEpoch != null && forEpoch != _serverEpoch) {
      await storage.delete(key: _kUiAccessKey);
      await storage.delete(key: _kUiRefreshKey);
      return;
    }
    final expiresAt = decodeJwtExp(accessToken);
    state = AsyncData(_current.copyWith(
      uiAccessToken: accessToken,
      uiRefreshToken: refreshToken,
      uiAccessTokenExpiresAt: expiresAt,
      // If decoder returned null (malformed token), wipe any stale
      // expiry from a previous good token so the Timer doesn't fire
      // off the old schedule.
      clearUiAccessTokenExpiresAt: expiresAt == null,
    ));
  }

  Future<void> updateUiLoginAccessToken(String accessToken,
      {int? forEpoch}) async {
    if (forEpoch != null && forEpoch != _serverEpoch) return;
    final storage = ref.read(secureStorageProvider);
    await storage.write(key: _kUiAccessKey, value: accessToken);
    if (forEpoch != null && forEpoch != _serverEpoch) {
      await storage.delete(key: _kUiAccessKey);
      return;
    }
    final expiresAt = decodeJwtExp(accessToken);
    state = AsyncData(_current.copyWith(
      uiAccessToken: accessToken,
      uiAccessTokenExpiresAt: expiresAt,
      clearUiAccessTokenExpiresAt: expiresAt == null,
    ));
  }

  Future<void> clearUiLoginTokens() async {
    final storage = ref.read(secureStorageProvider);
    await storage.delete(key: _kUiAccessKey);
    await storage.delete(key: _kUiRefreshKey);
    state = AsyncData(_current.copyWith(
      clearUiAccessToken: true,
      clearUiRefreshToken: true,
      clearUiAccessTokenExpiresAt: true,
    ));
  }

  /// Returns the cached refresh+access pair from state, or `null` if
  /// either is missing. Avoids hitting secure storage on every refresh.
  UiLoginTokens? uiLoginTokens() {
    final s = _current;
    if (s.uiAccessToken == null || s.uiRefreshToken == null) return null;
    return UiLoginTokens(
      accessToken: s.uiAccessToken!,
      refreshToken: s.uiRefreshToken!,
    );
  }

  // ---------- Basic credentials (migrated from SharedPreferences) ----------

  /// Removes the migrated basic-auth credential from secure storage.
  /// We don't track it in `state` (it's not in `AuthCredentialsState`)
  /// because basic auth has its own existing provider (`credentialsProvider`)
  /// for read access — this method exists solely to give the Logout flow
  /// a way to clear that entry post-migration.
  Future<void> clearBasicCredentials() =>
      ref.read(secureStorageProvider).delete(key: _kBasicCredentialsKey);

  /// Wipe every credential for a server switch. Clears in-memory state
  /// synchronously so nothing reads a stale cookie/token mid-delete.
  Future<void> clearAllForServerSwitch() async {
    _serverEpoch++;
    state = const AsyncData(AuthCredentialsState.empty());
    final storage = ref.read(secureStorageProvider);
    await Future.wait([
      storage.delete(key: _kPasswordKey),
      storage.delete(key: _kSimpleCookieKey),
      storage.delete(key: _kUiAccessKey),
      storage.delete(key: _kUiRefreshKey),
      storage.delete(key: _kBasicCredentialsKey),
    ]);
  }
}
