// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../global_providers/global_providers.dart';
import '../../account/domain/account_binding.dart';
import '../../settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import 'auth_session_transition.dart';
import 'basic_auth_migration.dart';
import 'credential_snapshot.dart';
import 'jwt_utils.dart';
import 'pending_tracker_oauth_store.dart';
import 'secure_credentials_provider.dart';
import 'simple_login_client.dart';

part 'auth_credentials_store.g.dart';

class UiLoginTokens {
  const UiLoginTokens({required this.accessToken, required this.refreshToken});
  final String accessToken;
  final String refreshToken;
}

/// Synchronously readable after preload so first-frame image requests can authenticate.
class AuthCredentialsState {
  const AuthCredentialsState({
    this.sessionEpoch = 0,
    this.sessionChanging = false,
    this.accountBinding,
    this.simpleLoginCookie,
    this.uiAccessToken,
    this.uiRefreshToken,
    this.uiAccessTokenExpiresAt,
  });

  const AuthCredentialsState.empty()
    : sessionEpoch = 0,
      sessionChanging = false,
      accountBinding = null,
      simpleLoginCookie = null,
      uiAccessToken = null,
      uiRefreshToken = null,
      uiAccessTokenExpiresAt = null;

  final AccountBinding? accountBinding;
  final int sessionEpoch;
  final bool sessionChanging;
  final String? simpleLoginCookie;
  final String? uiAccessToken;
  final String? uiRefreshToken;

  /// Derived from the access token on each update; null for missing or malformed tokens.
  final DateTime? uiAccessTokenExpiresAt;

  Map<String, String>? get uiAuthorizationHeader =>
      (uiAccessToken == null || uiAccessToken!.isEmpty)
      ? null
      : {'Authorization': 'Bearer $uiAccessToken'};

  /// Null for browser-managed sessions, whose cookies cannot be set from page code.
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

/// Loads credentials once at startup; mutations update memory and persist to secure storage.
/// Username alone remains in SharedPreferences.
@Riverpod(keepAlive: true)
class AuthCredentialsStore extends _$AuthCredentialsStore {
  @override
  Future<AuthCredentialsState> build() async {
    final vault = _vault;
    await vault.ensureLoaded(ref.read(sharedPreferencesProvider));
    final accessToken = vault[kUiAccessTokenSecureKey];
    final refreshToken = vault[kUiRefreshTokenSecureKey];
    return AuthCredentialsState(
      sessionEpoch: _sessionEpoch,
      sessionChanging: sessionChanging,
      accountBinding: AccountBinding.decode(
        vault[kUiAccountBindingSecureKey],
        accessToken: accessToken,
        refreshToken: refreshToken,
      ),
      simpleLoginCookie: vault[kSimpleLoginCookieSecureKey],
      uiAccessToken: accessToken,
      uiRefreshToken: refreshToken,
      uiAccessTokenExpiresAt: accessToken == null
          ? null
          : decodeJwtExp(accessToken),
    );
  }

  CredentialSnapshot get _vault => credentialSnapshot(
    ref.read(secureStorageProvider),
    ref.read(sharedPreferencesProvider),
  );

  Future<bool> _persist(Map<String, String?> changes) =>
      _vault.update(changes, ref.read(sharedPreferencesProvider));

  AuthCredentialsState get _current =>
      state.value ?? const AuthCredentialsState.empty();

  // Epoch guards discard delayed writes that race a server switch.
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
  final _handoverZone = Object();

  // Handovers preserve the account but bump serverEpoch; refresh can retry after them.
  int _handovers = 0;
  int get handovers => _handovers;

  /// Waiting for identity changes inside their own action would deadlock.
  bool get insideIdentityChange => Zone.current[_identityZone] == this;

  /// Handovers await no requests, so requests they spawn may wait for the handover.
  bool get insideHandover =>
      insideIdentityChange && Zone.current[_handoverZone] == this;

  /// Detaches spawned work from an identity-change zone when the change never awaits that work.
  R outsideIdentityChange<R>(R Function() body) =>
      runZoned(body, zoneValues: {_identityZone: null, _handoverZone: null});

  /// Waits up to [timeout]; returns false if an identity change is still running.
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
    final wasAdmitted = sessionAdmitted;
    var cancellationFailed = false;
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
      if (!preserveSession) {
        try {
          if (!await ref.read(pendingTrackerOAuthStoreProvider).cancel()) {
            throw StateError('Could not cancel pending tracker sign-in');
          }
        } catch (_) {
          cancellationFailed = true;
          throw StateError('Could not cancel pending tracker sign-in');
        }
      }
      return await runZoned(
        () async {
          final transition = preserveSession
              ? null
              : ref.read(authSessionTransitionProvider);
          return transition == null
              ? await action()
              : await transition.run(action);
        },
        zoneValues: {
          _identityZone: this,
          _handoverZone: preserveSession ? this : null,
        },
      );
    } finally {
      final restoreAdmission =
          cancellationFailed &&
          !_retired &&
          _activeSessionEpoch != null &&
          wasAdmitted;
      _identityChanges--;
      if (!preserveSession) {
        _sessionChanges--;
        _sessionEpoch++;
        if (restoreAdmission) _activeSessionEpoch = _sessionEpoch;
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


  Future<void> saveSimpleLoginCookie(String cookieValue, {int? forEpoch}) =>
      replaceCredentials(
        (epoch) => _saveSimpleLoginCookie(cookieValue, epoch),
        forEpoch: forEpoch,
      );

  Future<void> _saveSimpleLoginCookie(String cookieValue, int forEpoch) =>
      _mutate(() async {
        if (forEpoch != _serverEpoch) return;
        await _persist({kSimpleLoginCookieSecureKey: cookieValue});
        if (forEpoch != _serverEpoch) {
          await _persist({kSimpleLoginCookieSecureKey: null});
          return;
        }
        state = AsyncData(_current.copyWith(simpleLoginCookie: cookieValue));
      });

  Future<void> clearSimpleLoginCookie() => replaceCredentials(
    (_) => _mutate(() async {
      await _persist({kSimpleLoginCookieSecureKey: null});
      state = AsyncData(_current.copyWith(clearSimpleLoginCookie: true));
    }),
  );


  /// [forEpoch] discards or undoes writes if the server switches before persistence completes.
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
    await _persist({
      kUiAccessTokenSecureKey: accessToken,
      kUiRefreshTokenSecureKey: refreshToken,
      kUiAccountBindingSecureKey: binding?.encode(
        accessToken: accessToken,
        refreshToken: refreshToken,
      ),
    });
    if (forEpoch != _serverEpoch) return;
    final expiresAt = decodeJwtExp(accessToken);
    state = AsyncData(
      _current.copyWith(
        accountBinding: binding,
        clearAccountBinding: binding == null,
        uiAccessToken: accessToken,
        uiRefreshToken: refreshToken,
        uiAccessTokenExpiresAt: expiresAt,
        // Clear stale expiry when the replacement token cannot be decoded.
        clearUiAccessTokenExpiresAt: expiresAt == null,
      ),
    );
  }

  Future<void> updateUiLoginAccessToken(String accessToken, {int? forEpoch}) =>
      _mutate(() async {
        if (forEpoch != null && forEpoch != _serverEpoch) return;
        final binding = _current.accountBinding;
        final refresh = _current.uiRefreshToken;
        await _persist({
          kUiAccessTokenSecureKey: accessToken,
          kUiAccountBindingSecureKey: binding != null && refresh != null
              ? binding.encode(accessToken: accessToken, refreshToken: refresh)
              : null,
        });
        if (forEpoch != null && forEpoch != _serverEpoch) {
          await _persist({
            kUiAccessTokenSecureKey: null,
            kUiAccountBindingSecureKey: null,
          });
          return;
        }
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
    await _persist({
      kUiAccessTokenSecureKey: null,
      kUiRefreshTokenSecureKey: null,
      kUiAccountBindingSecureKey: null,
    });
    state = AsyncData(
      _current.copyWith(
        clearAccountBinding: true,
        clearUiAccessToken: true,
        clearUiRefreshToken: true,
        clearUiAccessTokenExpiresAt: true,
      ),
    );
  });

  /// Returns null unless both tokens are cached; never reads secure storage.
  UiLoginTokens? uiLoginTokens() {
    final s = _current;
    if (s.uiAccessToken == null || s.uiRefreshToken == null) return null;
    return UiLoginTokens(
      accessToken: s.uiAccessToken!,
      refreshToken: s.uiRefreshToken!,
    );
  }


  Future<void> clearBasicCredentials() async {
    await clearLegacyBasicCredentials(ref.read(sharedPreferencesProvider));
    await ref.read(credentialsProvider.notifier).set(null);
  }

  Future<void> clearAllForServerSwitch() => _mutate(() async {
    _serverEpoch++;
    _sessionEpoch++;
    await clearLegacyBasicCredentials(ref.read(sharedPreferencesProvider));
    state = AsyncData(
      const AuthCredentialsState.empty().copyWith(
        sessionEpoch: _sessionEpoch,
        sessionChanging: sessionChanging,
      ),
    );
    // Proxy headers describe the endpoint, not the account, so they stay.
    await _persist({
      kLegacyPasswordSecureKey: null,
      kSimpleLoginCookieSecureKey: null,
      kUiAccessTokenSecureKey: null,
      kUiRefreshTokenSecureKey: null,
      kUiAccountBindingSecureKey: null,
      kBasicCredentialsKey: null,
    });
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
