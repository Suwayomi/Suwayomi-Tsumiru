// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../account/domain/account_binding.dart';
import '../../settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import 'auth_session_transition.dart';
import 'jwt_utils.dart';
import 'secure_credentials_provider.dart';
import 'simple_login_client.dart';

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
    this.sessionEpoch = 0,
    this.sessionChanging = false,
    this.accountBinding,
    this.password,
    this.simpleLoginCookie,
    this.uiAccessToken,
    this.uiRefreshToken,
    this.uiAccessTokenExpiresAt,
  });

  const AuthCredentialsState.empty()
    : sessionEpoch = 0,
      sessionChanging = false,
      accountBinding = null,
      password = null,
      simpleLoginCookie = null,
      uiAccessToken = null,
      uiRefreshToken = null,
      uiAccessTokenExpiresAt = null;

  final AccountBinding? accountBinding;
  final int sessionEpoch;
  final bool sessionChanging;
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
  ///
  /// Null when the browser owns the session: it attaches the cookie itself,
  /// and a `Cookie` header set from page code is dropped either way.
  Map<String, String>? get simpleLoginCookieHeader =>
      (simpleLoginCookie == null ||
          simpleLoginCookie!.isEmpty ||
          simpleLoginCookie == kBrowserManagedSimpleSession)
      ? null
      : {'Cookie': simpleLoginCookie!};

  AuthCredentialsState copyWith({
    int? sessionEpoch,
    bool? sessionChanging,
    AccountBinding? accountBinding,
    bool clearAccountBinding = false,
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
      sessionEpoch: sessionEpoch ?? this.sessionEpoch,
      sessionChanging: sessionChanging ?? this.sessionChanging,
      accountBinding: clearAccountBinding
          ? null
          : (accountBinding ?? this.accountBinding),
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
  static const _kAccountBindingKey = 'auth.ui.accountBinding';
  static const _kBasicCredentialsKey = 'auth.basic.credentials';

  @override
  Future<AuthCredentialsState> build() async {
    final storage = ref.read(secureStorageProvider);
    final results = await Future.wait([
      storage.read(key: _kPasswordKey),
      storage.read(key: _kSimpleCookieKey),
      storage.read(key: _kUiAccessKey),
      storage.read(key: _kUiRefreshKey),
      storage.read(key: _kAccountBindingKey),
    ]);
    return AuthCredentialsState(
      sessionEpoch: _sessionEpoch,
      sessionChanging: sessionChanging,
      accountBinding: AccountBinding.decode(
        results[4],
        accessToken: results[2],
        refreshToken: results[3],
      ),
      password: results[0],
      simpleLoginCookie: results[1],
      uiAccessToken: results[2],
      uiRefreshToken: results[3],
      uiAccessTokenExpiresAt: results[2] == null
          ? null
          : decodeJwtExp(results[2]!),
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
  void invalidatePendingWrites() => _serverEpoch++;

  int _sessionEpoch = 0;
  int? _activeSessionEpoch;
  int get sessionEpoch => _sessionEpoch;
  bool get sessionAdmitted =>
      !sessionChanging &&
      (_activeSessionEpoch == null || _activeSessionEpoch == sessionEpoch);

  void activateSession() {
    if (sessionChanging) throw StateError('Authentication session is changing');
    _activeSessionEpoch = sessionEpoch;
    _publishSession();
  }

  bool Function() captureSession() {
    final epoch = sessionEpoch;
    return () => ref.mounted && sessionAdmitted && sessionEpoch == epoch;
  }

  int _sessionChanges = 0;
  bool _retired = false;
  bool get sessionChanging => _retired || _sessionChanges > 0;

  Future<void> retire() async {
    _retired = true;
    _sessionEpoch++;
    invalidatePendingWrites();
    _publishSession();
    await _mutationTail;
  }

  void _publishSession() {
    if (state.value == null) return;
    state = AsyncData(
      _current.copyWith(
        sessionEpoch: _sessionEpoch,
        sessionChanging: sessionChanging,
      ),
    );
  }

  int _identityChanges = 0;
  bool get identityChanging => _retired || _identityChanges > 0;
  Future<void> _mutationTail = Future<void>.value();
  Future<void> _identityTail = Future<void>.value();
  final _identityZone = Object();

  // Bumped when a session-preserving change (a LAN/remote endpoint handover)
  // starts. It still bumps [serverEpoch], so a refresh racing it is discarded
  // although the account never changed; this lets the coordinator tell that
  // case from a real sign-in change and retry instead of giving up.
  int _handovers = 0;
  int get handovers => _handovers;

  /// True inside a [withIdentityChange] action: waiting for identity changes
  /// to settle there would wait on itself.
  bool get insideIdentityChange => Zone.current[_identityZone] == this;

  /// Runs [body] as if outside any identity change. For work a change only
  /// spawns and never awaits, such as a socket connect started by the rebuild
  /// the change triggers: it inherits the change's zone through the microtasks
  /// that start it, and would otherwise be refused as if the change itself
  /// were asking, instead of waiting for it to finish.
  R outsideIdentityChange<R>(R Function() body) =>
      runZoned(body, zoneValues: {_identityZone: null});

  /// Waits (up to [timeout]) for every queued identity change to finish.
  /// Returns whether none is still running.
  Future<bool> identitySettled({required Duration timeout}) async {
    if (insideIdentityChange) return false;
    final deadline = DateTime.now().add(timeout);
    while (identityChanging && !_retired) {
      final left = deadline.difference(DateTime.now());
      if (left <= Duration.zero) return false;
      try {
        await _identityTail.timeout(left);
      } on TimeoutException {
        return false;
      }
    }
    return !identityChanging;
  }

  Future<T> _mutate<T>(Future<T> Function() action) {
    if (_retired) {
      return Future.error(StateError('Authentication session has ended'));
    }
    final initialized = future;
    final result = _mutationTail.then((_) async {
      await initialized;
      return action();
    });
    _mutationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<bool> commitForSession(int epoch, Future<void> Function() action) =>
      _mutate(() async {
        if (sessionChanging || sessionEpoch != epoch) return false;
        await action();
        return !sessionChanging && sessionEpoch == epoch;
      });

  Future<T> withIdentityChange<T>(
    Future<T> Function() action, {
    bool preserveSession = false,
    int? expectedEpoch,
  }) async {
    if (_retired) throw StateError('Authentication session has ended');
    if (_activeSessionEpoch != null &&
        _activeSessionEpoch != sessionEpoch &&
        Zone.current[_identityZone] != this) {
      throw StateError('Authentication session has ended');
    }
    if (expectedEpoch != null &&
        (expectedEpoch != _serverEpoch ||
            (identityChanging && Zone.current[_identityZone] != this))) {
      throw StateError('Authentication session changed');
    }
    if (Zone.current[_identityZone] == this) return action();
    _identityChanges++;
    if (preserveSession) _handovers++;
    if (!preserveSession) {
      _sessionChanges++;
      _sessionEpoch++;
    }
    _publishSession();
    final previous = _identityTail;
    final finished = Completer<void>();
    _identityTail = finished.future;
    try {
      await previous;
      invalidatePendingWrites();
      await _mutationTail;
      return await runZoned(() async {
        final transition = preserveSession
            ? null
            : ref.read(authSessionTransitionProvider);
        return transition == null
            ? await action()
            : await transition.run(action);
      }, zoneValues: {_identityZone: this});
    } finally {
      _identityChanges--;
      if (!preserveSession) {
        _sessionChanges--;
        _sessionEpoch++;
      }
      invalidatePendingWrites();
      _publishSession();
      finished.complete();
    }
  }

  Future<void> replaceCredentials(
    Future<void> Function(int epoch) action, {
    int? forEpoch,
  }) async {
    if (forEpoch != null &&
        (forEpoch != _serverEpoch ||
            (identityChanging && Zone.current[_identityZone] != this))) {
      return;
    }
    await withIdentityChange(() => action(_serverEpoch));
  }

  // ---------- Password ----------

  Future<void> savePassword(String password, {int? forEpoch}) =>
      _mutate(() async {
        if (forEpoch != null && forEpoch != _serverEpoch) return;
        final storage = ref.read(secureStorageProvider);
        await storage.write(key: _kPasswordKey, value: password);
        if (forEpoch != null && forEpoch != _serverEpoch) {
          await storage.delete(key: _kPasswordKey);
          return;
        }
        state = AsyncData(_current.copyWith(password: password));
      });

  Future<void> clearPassword() => _mutate(() async {
    await ref.read(secureStorageProvider).delete(key: _kPasswordKey);
    state = AsyncData(_current.copyWith(clearPassword: true));
  });

  // ---------- Simple Login ----------

  Future<void> saveSimpleLoginCookie(String cookieValue, {int? forEpoch}) =>
      replaceCredentials(
        (epoch) => _saveSimpleLoginCookie(cookieValue, epoch),
        forEpoch: forEpoch,
      );

  Future<void> _saveSimpleLoginCookie(String cookieValue, int forEpoch) =>
      _mutate(() async {
        if (forEpoch != _serverEpoch) return;
        final storage = ref.read(secureStorageProvider);
        await storage.write(key: _kSimpleCookieKey, value: cookieValue);
        if (forEpoch != _serverEpoch) {
          await storage.delete(key: _kSimpleCookieKey);
          return;
        }
        state = AsyncData(_current.copyWith(simpleLoginCookie: cookieValue));
      });

  Future<void> clearSimpleLoginCookie() => replaceCredentials(
    (_) => _mutate(() async {
      await ref.read(secureStorageProvider).delete(key: _kSimpleCookieKey);
      state = AsyncData(_current.copyWith(clearSimpleLoginCookie: true));
    }),
  );

  // ---------- UI Login ----------

  /// [forEpoch]: discards (or undoes) the write if a switch bumps [serverEpoch]
  /// before or during the storage write.
  Future<void> saveUiLoginTokens({
    required String accessToken,
    required String refreshToken,
    AccountBinding? binding,
    int? forEpoch,
  }) => replaceCredentials(
    (epoch) => _saveUiLoginTokens(accessToken, refreshToken, epoch, binding),
    forEpoch: forEpoch,
  );

  Future<bool> refreshUiLoginTokens({
    required String accessToken,
    required String refreshToken,
    required String originalRefreshToken,
    required int forEpoch,
  }) => _mutate(() async {
    if (identityChanging ||
        forEpoch != _serverEpoch ||
        _current.uiRefreshToken != originalRefreshToken) {
      return false;
    }
    await _writeUiLoginTokens(
      accessToken,
      refreshToken,
      forEpoch,
      _current.accountBinding,
    );
    return forEpoch == _serverEpoch && _current.uiAccessToken == accessToken;
  });

  Future<void> _saveUiLoginTokens(
    String accessToken,
    String refreshToken,
    int epoch,
    AccountBinding? binding,
  ) => _mutate(
    () => _writeUiLoginTokens(accessToken, refreshToken, epoch, binding),
  );

  Future<void> _writeUiLoginTokens(
    String accessToken,
    String refreshToken,
    int forEpoch,
    AccountBinding? binding,
  ) async {
    if (forEpoch != _serverEpoch) return;
    final storage = ref.read(secureStorageProvider);
    await storage.write(key: _kUiAccessKey, value: accessToken);
    await storage.write(key: _kUiRefreshKey, value: refreshToken);
    if (forEpoch != _serverEpoch) {
      await storage.delete(key: _kUiAccessKey);
      await storage.delete(key: _kUiRefreshKey);
      return;
    }
    await storage.write(
      key: _kAccountBindingKey,
      value: binding?.encode(
        accessToken: accessToken,
        refreshToken: refreshToken,
      ),
    );
    if (forEpoch != _serverEpoch) return;
    final expiresAt = decodeJwtExp(accessToken);
    state = AsyncData(
      _current.copyWith(
        accountBinding: binding,
        clearAccountBinding: binding == null,
        uiAccessToken: accessToken,
        uiRefreshToken: refreshToken,
        uiAccessTokenExpiresAt: expiresAt,
        // If decoder returned null (malformed token), wipe any stale
        // expiry from a previous good token so the Timer doesn't fire
        // off the old schedule.
        clearUiAccessTokenExpiresAt: expiresAt == null,
      ),
    );
  }

  Future<void> updateUiLoginAccessToken(String accessToken, {int? forEpoch}) =>
      _mutate(() async {
        if (forEpoch != null && forEpoch != _serverEpoch) return;
        final storage = ref.read(secureStorageProvider);
        await storage.write(key: _kUiAccessKey, value: accessToken);
        if (forEpoch != null && forEpoch != _serverEpoch) {
          await storage.delete(key: _kUiAccessKey);
          return;
        }
        final binding = _current.accountBinding;
        final refresh = _current.uiRefreshToken;
        await storage.write(
          key: _kAccountBindingKey,
          value: binding != null && refresh != null
              ? binding.encode(accessToken: accessToken, refreshToken: refresh)
              : null,
        );
        if (forEpoch != null && forEpoch != _serverEpoch) return;
        final expiresAt = decodeJwtExp(accessToken);
        state = AsyncData(
          _current.copyWith(
            uiAccessToken: accessToken,
            uiAccessTokenExpiresAt: expiresAt,
            clearUiAccessTokenExpiresAt: expiresAt == null,
          ),
        );
      });

  Future<void> clearUiLoginTokens({int? forEpoch}) => forEpoch == null
      ? replaceCredentials((epoch) => _clearUiLoginTokens(epoch))
      : _clearUiLoginTokens(forEpoch);

  Future<void> _clearUiLoginTokens(int forEpoch) => _mutate(() async {
    if (forEpoch != _serverEpoch) return;
    final storage = ref.read(secureStorageProvider);
    await storage.delete(key: _kUiAccessKey);
    await storage.delete(key: _kUiRefreshKey);
    await storage.delete(key: _kAccountBindingKey);
    state = AsyncData(
      _current.copyWith(
        clearAccountBinding: true,
        clearUiAccessToken: true,
        clearUiRefreshToken: true,
        clearUiAccessTokenExpiresAt: true,
      ),
    );
  });

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
      ref.read(credentialsProvider.notifier).set(null);

  Future<void> clearAllForServerSwitch() => _mutate(() async {
    _serverEpoch++;
    _sessionEpoch++;
    state = AsyncData(
      const AuthCredentialsState.empty().copyWith(
        sessionEpoch: _sessionEpoch,
        sessionChanging: sessionChanging,
      ),
    );
    final storage = ref.read(secureStorageProvider);
    await Future.wait([
      storage.delete(key: _kPasswordKey),
      storage.delete(key: _kSimpleCookieKey),
      storage.delete(key: _kUiAccessKey),
      storage.delete(key: _kUiRefreshKey),
      storage.delete(key: _kAccountBindingKey),
      storage.delete(key: _kBasicCredentialsKey),
    ]);
    ref.invalidate(credentialsProvider);
    await ref.read(credentialsProvider.future);
  });
}

bool Function() watchAuthSession(Ref ref) {
  ref.watch(
    authCredentialsStoreProvider.select(
      (value) => (
        value.value?.sessionEpoch ?? 0,
        value.value?.sessionChanging ?? false,
      ),
    ),
  );
  final store = ref.read(authCredentialsStoreProvider.notifier);
  return store.captureSession();
}
