// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async'; // Completer + Timer — required by single-flight + proactive refresh
import 'dart:convert';

import 'package:flutter/foundation.dart'; // debugPrint
import 'package:graphql/client.dart';
import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../constants/db_keys.dart';
import '../../../constants/enum.dart';
import '../../../global_providers/global_providers.dart';
// Input types are defined in the schema file and NOT re-exported by
// auth.graphql.dart, so we import the schema directly.
import '../../../graphql/__generated__/schema.graphql.dart'
    show Input$LoginInput, Input$RefreshTokenInput;
import '../../../utils/crash/diagnostics.dart';
import '../../account/data/account_notice.dart';
import '../../account/data/account_session_repository.dart';
import '../../account/domain/account_binding.dart';
import '../../offline/data/offline_server_identity_repository.dart';
import '../../onboarding/data/server_resolver.dart'
    show authProbeAuthorized, basicAuthConfirms;
import '../../settings/presentation/general/timeout_settings/timeout_settings_section.dart';
import '../../settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import 'auth_credentials_store.dart';
import 'auth_state.dart';
import 'basic_credentials_rejected.dart';
import 'custom_headers_store.dart';
import 'graphql/__generated__/auth.graphql.dart';
import 'jwt_utils.dart';
import 'simple_login_client.dart';

part 'auth_coordinator.g.dart';

/// Result of a Test Connection attempt.
sealed class TestConnectionResult {
  const TestConnectionResult();
}

class TestConnectionSuccess extends TestConnectionResult {
  const TestConnectionSuccess();
}

class TestConnectionFailure extends TestConnectionResult {
  const TestConnectionFailure(this.kind, [this.detail]);
  final TestConnectionFailureKind kind;
  final String? detail;
}

enum TestConnectionFailureKind {
  network,
  tls,
  invalidCredentials,
  wrongAuthMode,
  unexpectedShape,
  insecureTransport,
  browserSession,
}

/// Maps a thrown error to a typed [TestConnectionFailure]. Used by both
/// `testConnection` and the credentials popup's Save path so both surface
/// the same friendly message instead of a raw exception toString().
///
/// TLS errors (`HandshakeException: Wrong version number`) are checked
/// BEFORE network errors because their toString() also contains tokens
/// like "connection" that would otherwise collapse them into a generic
/// network failure.
TestConnectionFailure classifyAuthError(Object e) {
  if (e is BasicCredentialsRejected) {
    return const TestConnectionFailure(
      TestConnectionFailureKind.invalidCredentials,
    );
  }
  if (e is SimpleLoginAuthFailure) {
    return const TestConnectionFailure(
      TestConnectionFailureKind.invalidCredentials,
    );
  }
  if (e is SimpleLoginSessionFailure) {
    return const TestConnectionFailure(
      TestConnectionFailureKind.browserSession,
    );
  }
  if (e is SimpleLoginShapeFailure) {
    return TestConnectionFailure(
      TestConnectionFailureKind.unexpectedShape,
      e.message,
    );
  }
  final msg = e.toString().toLowerCase();
  if (msg.contains('unauthor') ||
      msg.contains('forbidden') ||
      // Suwayomi's UI-login rejection ("Incorrect username or password.")
      // and Simple Login's variants — none contain "unauthorized", so match
      // them explicitly rather than fall through to the scary "wrong URL?".
      msg.contains('incorrect username or password') ||
      msg.contains('invalid username or password') ||
      msg.contains('invalid credentials')) {
    return const TestConnectionFailure(
      TestConnectionFailureKind.invalidCredentials,
    );
  }
  if (msg.contains('handshake') ||
      msg.contains('wrong version') ||
      msg.contains('certificate') ||
      msg.contains('tls') ||
      msg.contains(' ssl')) {
    return const TestConnectionFailure(TestConnectionFailureKind.tls);
  }
  if (msg.contains('socket') ||
      msg.contains('timeout') ||
      msg.contains('host') ||
      msg.contains('connection')) {
    return const TestConnectionFailure(TestConnectionFailureKind.network);
  }
  return TestConnectionFailure(
    TestConnectionFailureKind.unexpectedShape,
    e.toString(),
  );
}

/// Outcome of a refresh attempt. Top-level sealed type — DECLARED HERE
/// (above [AuthCoordinator]) so the class body that references it can
/// stay contiguous. This placement matters: in round 2 the sealed
/// classes were inserted MID-CLASS by accident, which forced
/// `testConnection` to fall outside the class and broke compilation.
sealed class RefreshOutcome {
  const RefreshOutcome();
  const factory RefreshOutcome.success(String newAccessToken) = RefreshSuccess;
  const factory RefreshOutcome.authFailure() = RefreshAuthFailure;
  const factory RefreshOutcome.transientFailure(Object error) =
      RefreshTransientFailure;
}

class RefreshSuccess extends RefreshOutcome {
  const RefreshSuccess(this.newAccessToken);
  final String newAccessToken;
}

class RefreshAuthFailure extends RefreshOutcome {
  const RefreshAuthFailure();
}

class RefreshTransientFailure extends RefreshOutcome {
  const RefreshTransientFailure(this.error);
  final Object error;
}

/// One-line, token-free summary of [outcome] for the diagnostic log: the new
/// token's remaining lifetime on success, the error's type and first line on
/// a transient failure. `null` means no refresh was due.
String describeRefreshOutcome(RefreshOutcome? outcome, {DateTime? now}) =>
    switch (outcome) {
      null => 'outcome=not-due',
      RefreshSuccess(:final newAccessToken) =>
        'outcome=success ${describeTokenExpiry(newAccessToken, now: now)}',
      RefreshAuthFailure() => 'outcome=auth-failure',
      RefreshTransientFailure(:final error) =>
        'outcome=transient cause=${describeDiagnosticError(error)}',
    };

/// `expIn=<seconds>` (negative once expired) for a JWT, `exp=unknown` when it
/// can't be decoded, `token=none` for a missing one. Never the token itself.
String describeTokenExpiry(String? token, {DateTime? now}) {
  if (token == null || token.isEmpty) return 'token=none';
  final exp = decodeJwtExp(token);
  if (exp == null) return 'exp=unknown';
  return 'expIn=${exp.difference(now ?? DateTime.now().toUtc()).inSeconds}s';
}

/// `<Type>: <first line>` of [error], capped so a server stack trace packed
/// into a message can't flood the log.
String describeDiagnosticError(Object error) {
  final first = error.toString().split('\n').first.trim();
  final text = first.length > 160 ? '${first.substring(0, 160)}…' : first;
  return '${error.runtimeType}: $text';
}

Expando<Completer<RefreshOutcome>> _refreshInFlight = Expando();

@visibleForTesting
void debugResetAuthCoordinatorSingleFlight() {
  _refreshInFlight = Expando();
}

/// Extracts an HTTP status code from a graphql_flutter [LinkException],
/// or `null` if the exception isn't an HTTP-layer one. Used by
/// [AuthCoordinator._refreshUiAccessTokenImpl] to tell auth failures
/// (401/403) from transient failures (sockets, 5xx, timeout). Defined
/// at file scope so tests can drive it without standing up an
/// AuthCoordinator. — Codex round-3 finding.
int? _httpStatusOfLinkException(LinkException ex) {
  if (ex is HttpLinkServerException) {
    return ex.response.statusCode;
  }
  // ResponseFormatException / ServerException / NetworkException etc.
  // don't carry a status code — treat as transient.
  return null;
}

/// Orchestrates login, re-auth, and test-connection flows for the two new
/// auth modes. Pure logic — the UI calls into this and observes the
/// resulting state via [AuthCredentialsStore] and [NeedsReauth].
///
/// **Proactive refresh** (this file's reason for existing post-v0.2.0):
/// ui_login access tokens expire after ~5 min by default. Image fetches
/// bypass the GraphQL auth link, so when no GraphQL traffic surfaces a
/// 401, the token quietly expires and every subsequent image breaks.
/// We schedule a Timer at `exp - proactiveRefreshLead` to rotate the
/// token before any image request can see it expired. On transient
/// refresh failures we reschedule via [_backoffSchedule]. On auth
/// failure we cancel and surface the existing re-auth banner.
@Riverpod(keepAlive: true)
class AuthCoordinator extends _$AuthCoordinator {
  /// How long before the access token's `exp` to fire a refresh. Sized
  /// to comfortably cover round-trip + reader prefetch latency.
  static const Duration proactiveRefreshLead = Duration(seconds: 60);

  /// Maximum delay we'll wait before firing a proactive refresh. Caps
  /// JWTs with weirdly-far-future `exp` claims so the Timer isn't
  /// scheduled for a duration that survives device reboot.
  static const Duration _maxProactiveDelay = Duration(hours: 24);

  /// Backoff schedule for transient-failure retries (R2-3). One-shot
  /// Dart `Timer` doesn't re-fire on its own, so we explicitly hop
  /// through this list and cap at the last entry.
  static const List<Duration> _backoffSchedule = [
    Duration(seconds: 30),
    Duration(seconds: 60),
    Duration(seconds: 120),
    Duration(seconds: 300),
  ];

  Timer? _proactiveRefreshTimer;
  int _proactiveBackoffStep = 0;

  @override
  void build() {
    // Listen to credentials changes and (re)schedule the proactive
    // refresh whenever a ui_login access token is present. Cancel when
    // tokens are cleared (logout, mode switch).
    ref.listen<AsyncValue<AuthCredentialsState>>(authCredentialsStoreProvider, (
      prev,
      next,
    ) {
      final state = next.value;
      if (state == null) return;
      if (!ref.read(authCredentialsStoreProvider.notifier).sessionAdmitted) {
        _cancelProactiveRefresh();
        return;
      }
      if (state.uiAccessToken == null || state.uiAccessTokenExpiresAt == null) {
        _cancelProactiveRefresh();
        return;
      }
      // Re-schedule only when the expiry actually changed (e.g.
      // post-refresh, post-login, post-bootstrap). Cheap idempotent
      // reschedule is also fine — we cancel any existing Timer first.
      final prevExpiry = prev?.value?.uiAccessTokenExpiresAt;
      if (prevExpiry == state.uiAccessTokenExpiresAt &&
          _proactiveRefreshTimer != null) {
        return;
      }
      _scheduleProactiveRefresh();
    }, fireImmediately: true);
    ref.onDispose(_cancelProactiveRefresh);
  }

  void _scheduleProactiveRefresh() {
    _proactiveRefreshTimer?.cancel();
    _proactiveRefreshTimer = null;

    final expiresAt = ref
        .read(authCredentialsStoreProvider)
        .value
        ?.uiAccessTokenExpiresAt;
    if (expiresAt == null) return;

    final now = DateTime.now().toUtc();
    var delay = expiresAt.difference(now) - proactiveRefreshLead;
    if (delay.isNegative) delay = Duration.zero;
    if (delay > _maxProactiveDelay) delay = _maxProactiveDelay;

    _proactiveRefreshTimer = Timer(delay, () {
      _proactiveRefreshTimer = null;
      _firePeriodicRefresh();
    });
  }

  /// Schedules a transient-failure backoff Timer. Cancels any existing
  /// Timer first so we never have two pending.
  void _scheduleBackoffRefresh() {
    _proactiveRefreshTimer?.cancel();
    final stepIndex = _proactiveBackoffStep.clamp(
      0,
      _backoffSchedule.length - 1,
    );
    final delay = _backoffSchedule[stepIndex];
    _proactiveBackoffStep++;
    _proactiveRefreshTimer = Timer(delay, () {
      _proactiveRefreshTimer = null;
      _firePeriodicRefresh();
    });
  }

  Future<void> _firePeriodicRefresh() async {
    try {
      final gqlClient = ref.read(unauthenticatedGraphQlClientProvider);
      final outcome = await refreshUiAccessToken(
        gqlClient: gqlClient,
        trigger: 'timer',
      );
      if (outcome is RefreshSuccess) {
        _proactiveBackoffStep = 0;
        _scheduleProactiveRefresh();
      } else if (outcome is RefreshTransientFailure) {
        _scheduleBackoffRefresh();
      }
      // RefreshAuthFailure: tokens are cleared and the credentials
      // listener will fire with uiAccessToken=null, triggering
      // _cancelProactiveRefresh. No work here.
    } catch (e, st) {
      debugPrint('proactive refresh callback raised: $e\n$st');
      // Treat unexpected throws as transient — keep trying.
      _scheduleBackoffRefresh();
    }
  }

  /// Cancels any pending Timer and resets the backoff step. Safe to
  /// call repeatedly.
  void _cancelProactiveRefresh() {
    _proactiveRefreshTimer?.cancel();
    _proactiveRefreshTimer = null;
    _proactiveBackoffStep = 0;
  }

  @visibleForTesting
  bool get debugHasProactiveTimer => _proactiveRefreshTimer != null;

  // ---------- Verify-only paths (no persistence) ----------
  //
  // These run the same network round-trips as the real login flows but
  // do NOT touch secure storage. Used by the credentials popup's Test
  // Connection button so a user can verify without committing anything
  // — clicking Cancel must leave the existing config untouched.
  //
  // **Caveat for simple_login (R2-11):** `verifySimpleCredentials` calls
  // `POST /login.html`, which creates a server-side session and returns a
  // cookie. Discarding the cookie does NOT delete the session — Suwayomi
  // will accumulate orphan sessions if the user hammers Test. The
  // existing simple_login docs don't expose a logout-without-cookie
  // endpoint, so we accept this as a documented limitation. UX guidance:
  // the popup should treat Test as "soft commit" — successive Tests
  // overwrite each other server-side, and Save reuses the most recent
  // verified cookie (see Task 17) so a typical Test → Save sequence
  // produces exactly one session.

  /// Verifies Simple Login credentials by POSTing to /login.html. Returns
  /// the session cookie on success; throws on failure. Caller decides
  /// whether to persist (via [loginSimple]) or discard.
  Future<String> verifySimpleCredentials({
    required String serverBaseUrl,
    required String username,
    required String password,
  }) async {
    final client = SimpleLoginClient(
      timeout: Duration(
        milliseconds:
            ref.read(serverRequestTimeoutProvider) ??
            DBKeys.serverRequestTimeout.initial as int,
      ),
    );
    try {
      return await client.login(
        serverBaseUrl: serverBaseUrl,
        username: username,
        password: password,
        extraHeaders: ref.read(customHttpHeadersProvider).value,
      );
    } finally {
      client.close();
    }
  }

  /// Verifies UI Login credentials by firing the `login` mutation.
  /// Returns the token pair on success; throws on failure. Caller
  /// decides whether to persist (via [loginUi]) or discard.
  Future<UiLoginTokens> verifyUiCredentials({
    required GraphQLClient gqlClient,
    required String username,
    required String password,
  }) async {
    final result = await gqlClient.mutate$Login(
      Options$Mutation$Login(
        variables: Variables$Mutation$Login(
          input: Input$LoginInput(username: username, password: password),
        ),
      ),
    );
    if (result.hasException) {
      throw result.exception!;
    }
    final payload = result.parsedData?.login;
    if (payload == null) {
      throw Exception('login mutation returned null payload');
    }
    return UiLoginTokens(
      accessToken: payload.accessToken,
      refreshToken: payload.refreshToken,
    );
  }

  // ---------- Persisting login paths ----------

  /// Verifies Basic credentials against the server AND persists them.
  ///
  /// basic_auth has no login round-trip, so this probes with the header the
  /// app would go on to send. Without it a typo was stored happily and the
  /// user was shown as signed in while every request came back 401.
  Future<void> loginBasic({
    required String serverBaseUrl,
    required String username,
    required String password,
  }) async {
    final store = ref.read(authCredentialsStoreProvider.notifier);
    await store.withIdentityChange(() async {
      final epoch = store.serverEpoch;
      final client = http.Client();
      final bool authorized;
      try {
        authorized = await authProbeAuthorized(
          serverBaseUrl,
          client: client,
          basic: '$username:$password',
          extraHeaders: ref.read(customHttpHeadersProvider).value,
        );
      } finally {
        client.close();
      }
      if (!authorized) throw const BasicCredentialsRejected();
      await ref
          .read(credentialsProvider.notifier)
          .set(
            'Basic ${base64.encode(utf8.encode('$username:$password'))}',
            forEpoch: epoch,
          );
      await store.savePassword(password, forEpoch: epoch);
      ref.read(needsReauthProvider.notifier).set(false);
    }, expectedEpoch: store.serverEpoch);
  }

  /// Performs Simple Login AND persists the resulting cookie + password.
  /// Equivalent to `verifySimpleCredentials` + a store write. Used by
  /// the credentials popup's Save button.
  Future<void> loginSimple({
    required String serverBaseUrl,
    required String username,
    required String password,
  }) async {
    final store = ref.read(authCredentialsStoreProvider.notifier);
    // Capture before verify so a switch mid-login can't persist creds for the new host.
    await store.withIdentityChange(() async {
      final epoch = store.serverEpoch;
      final cookie = await verifySimpleCredentials(
        serverBaseUrl: serverBaseUrl,
        username: username,
        password: password,
      );
      await store.saveSimpleLoginCookie(cookie, forEpoch: epoch);
      await store.savePassword(password, forEpoch: epoch);
      ref.read(needsReauthProvider.notifier).set(false);
    }, expectedEpoch: store.serverEpoch);
  }

  /// Performs UI Login AND persists both tokens + password.
  Future<void> loginUi({
    required GraphQLClient gqlClient,
    required String username,
    required String password,
  }) async {
    final store = ref.read(authCredentialsStoreProvider.notifier);
    await store.withIdentityChange(() async {
      final epoch = store.serverEpoch;
      final address = ref.read(currentServerAddressProvider);
      final tokens = await verifyUiCredentials(
        gqlClient: gqlClient,
        username: username,
        password: password,
      );
      await adoptUiLoginTokens(
        gqlClient: gqlClient,
        tokens: tokens,
        forEpoch: epoch,
        address: address,
        username: username,
        password: password,
      );
    }, expectedEpoch: store.serverEpoch);
  }

  Future<void> adoptUiLoginTokens({
    required GraphQLClient gqlClient,
    required UiLoginTokens tokens,
    required int forEpoch,
    required String address,
    required String username,
    String? password,
    AccountBinding? expectedBinding,
  }) async {
    final store = ref.read(authCredentialsStoreProvider.notifier);
    await store.withIdentityChange(() async {
      final epoch = store.serverEpoch;
      if (address != ref.read(currentServerAddressProvider)) {
        throw StateError('Authentication server changed');
      }
      final accountClient = GraphQLClient(
        link: AuthLink(
          getToken: () => 'Bearer ${tokens.accessToken}',
        ).concat(gqlClient.link),
        cache: GraphQLCache(),
        defaultPolicies: DefaultPolicies(
          query: Policies(fetch: FetchPolicy.noCache),
        ),
        queryRequestTimeout: gqlClient.queryManager.requestTimeout,
      );
      final binding = await AccountSessionRepository(
        accountClient,
      ).resolve(address: address, loginUsername: username);
      if (epoch != store.serverEpoch ||
          address != ref.read(currentServerAddressProvider)) {
        throw StateError('Authentication session changed');
      }
      // userId + catalogId pin the account to a server instance. The address
      // is only how we reached it, and the endpoint resolver rewrites it on a
      // Wi-Fi/mobile switch, so comparing it rejects the same account.
      if (expectedBinding != null &&
          (binding.userId != expectedBinding.userId ||
              binding.catalogId != expectedBinding.catalogId)) {
        throw StateError('Authentication account changed');
      }
      await store.saveUiLoginTokens(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        binding: binding,
        forEpoch: epoch,
      );
      if (password != null) {
        await store.savePassword(password, forEpoch: epoch);
      }
      await ref.read(accountNoticeProvider.notifier).set(null);
      ref.read(needsReauthProvider.notifier).set(false);
    }, expectedEpoch: forEpoch);
  }

  /// [trigger] names the caller in the `auth-refresh` diagnostic, so a field
  /// log shows which path refreshed (or failed to) and when.
  Future<RefreshOutcome> refreshUiAccessToken({
    required GraphQLClient gqlClient,
    String trigger = 'other',
  }) async {
    final store = ref.read(authCredentialsStoreProvider.notifier);
    final inFlight = _refreshInFlight[store];
    if (inFlight != null) {
      recordDiagnostic(
        '[${DateTime.now().toIso8601String()}] auth-refresh: '
        'trigger=$trigger joined-in-flight\n',
      );
      return inFlight.future;
    }

    final completer = Completer<RefreshOutcome>();
    _refreshInFlight[store] = completer;
    try {
      final outcome = await _refreshUiAccessTokenImpl(gqlClient);
      recordDiagnostic(
        '[${DateTime.now().toIso8601String()}] auth-refresh: '
        'trigger=$trigger ${describeRefreshOutcome(outcome)}\n',
      );
      completer.complete(outcome);
      return outcome;
    } catch (e, st) {
      // _refreshUiAccessTokenImpl handles its own errors; this catch is
      // strictly defensive. A throw here is a programmer error, not an
      // auth/network failure — surface it transient so we don't wipe
      // tokens for the wrong reason.
      debugPrint('refreshUiAccessToken: unexpected throw: $e\n$st');
      final outcome = RefreshOutcome.transientFailure(e);
      recordDiagnostic(
        '[${DateTime.now().toIso8601String()}] auth-refresh: '
        'trigger=$trigger threw ${describeRefreshOutcome(outcome)}\n',
      );
      completer.complete(outcome);
      return outcome;
    } finally {
      if (identical(_refreshInFlight[store], completer)) {
        _refreshInFlight[store] = null;
      }
    }
  }

  Future<RefreshOutcome> _refreshUiAccessTokenImpl(
    GraphQLClient gqlClient,
  ) async {
    final store = ref.read(authCredentialsStoreProvider.notifier);
    // A switch bumping the epoch mid-refresh discards the write below.
    final startEpoch = store.serverEpoch;
    if (store.identityChanging || !store.sessionAdmitted) {
      return RefreshOutcome.transientFailure(
        StateError('Credentials are changing'),
      );
    }
    // "No tokens" is only meaningful once the store has actually loaded.
    // Before hydration (or after a failed secure-storage read) the snapshot is
    // empty even when tokens exist on disk — declaring the session dead there
    // shows a false "Session expired" and can cascade into wiping good
    // tokens. Treat it as transient; the next trigger re-reads a settled store.
    final storeState = ref.read(authCredentialsStoreProvider);
    if (storeState.value == null) {
      // A failed hydration would otherwise stay AsyncError forever (nothing
      // rebuilds the store) and pin the backoff loop — re-run it.
      if (storeState.hasError) ref.invalidate(authCredentialsStoreProvider);
      return RefreshOutcome.transientFailure(
        StateError('credentials store not hydrated'),
      );
    }
    final tokens = store.uiLoginTokens();
    if (tokens == null) {
      return const RefreshOutcome.authFailure();
    }

    final QueryResult<Mutation$RefreshToken> result;
    try {
      result = await gqlClient.mutate$RefreshToken(
        Options$Mutation$RefreshToken(
          variables: Variables$Mutation$RefreshToken(
            input: Input$RefreshTokenInput(refreshToken: tokens.refreshToken),
          ),
        ),
      );
    } catch (e, st) {
      // Network/socket/timeout — DON'T clear tokens. The refresh token
      // may still be perfectly good; we just couldn't reach the server.
      debugPrint('refreshToken network error: $e\n$st');
      return RefreshOutcome.transientFailure(e);
    }

    if (store.identityChanging || store.serverEpoch != startEpoch) {
      return RefreshOutcome.transientFailure(
        StateError('Credentials changed during refresh'),
      );
    }

    final exception = result.exception;
    if (exception != null) {
      // Distinguish network-style GraphQL errors (linkException) from
      // server-rejected auth errors (graphqlErrors with 401-ish status).
      //
      // Codex round-3 finding: not every linkException is transient.
      // Suwayomi's refresh-token rejection can arrive as
      // `HttpLinkServerException` with HTTP 401/403 — that's an AUTH
      // failure, not a network blip. We need to inspect the inner
      // exception's status code before classifying.
      final link = exception.linkException;
      if (link != null) {
        final status = _httpStatusOfLinkException(link);
        if (status == 401 || status == 403) {
          // Server actively rejected the refresh token at the HTTP
          // layer. Treat as auth failure.
          await store.clearUiLoginTokens(forEpoch: startEpoch);
          if (store.identityChanging || store.serverEpoch != startEpoch) {
            return RefreshOutcome.transientFailure(
              StateError('Credentials changed during refresh'),
            );
          }
          ref.read(needsReauthProvider.notifier).set(true);
          return const RefreshOutcome.authFailure();
        }
        // Other link exceptions (socket, timeout, server 5xx) are
        // transient — keep tokens, let the user retry.
        return RefreshOutcome.transientFailure(exception);
      }
      // GraphQL errors (non-link) here mean the server actively
      // rejected the refresh token at the GraphQL layer — clear and
      // prompt re-auth.
      await store.clearUiLoginTokens(forEpoch: startEpoch);
      if (store.identityChanging || store.serverEpoch != startEpoch) {
        return RefreshOutcome.transientFailure(
          StateError('Credentials changed during refresh'),
        );
      }
      ref.read(needsReauthProvider.notifier).set(true);
      return const RefreshOutcome.authFailure();
    }

    final newAccess = result.parsedData?.refreshToken.accessToken;
    if (newAccess == null) {
      // No exception, but no token either — treat as auth failure.
      await store.clearUiLoginTokens(forEpoch: startEpoch);
      if (store.identityChanging || store.serverEpoch != startEpoch) {
        return RefreshOutcome.transientFailure(
          StateError('Credentials changed during refresh'),
        );
      }
      ref.read(needsReauthProvider.notifier).set(true);
      return const RefreshOutcome.authFailure();
    }

    // R2-1, R2-2: Re-read auth mode IMMEDIATELY before applying the
    // refreshed token. The user may have switched to basic_auth or
    // simple_login between the moment we issued the refresh and the
    // moment its response arrived. Persisting a ui_login token here
    // would resurrect dead credentials and break the now-active mode.
    // Single-flight protects us from duplicate refreshes but does NOT
    // protect us from stale-mode writes — that's this check's job.
    final currentMode =
        ref.read(authTypeKeyProvider) ?? DBKeys.authType.initial;
    if (currentMode != AuthType.uiLogin) {
      debugPrint(
        'refresh result discarded: auth mode changed to $currentMode mid-refresh',
      );
      return RefreshOutcome.transientFailure(
        Exception('auth mode changed during refresh'),
      );
    }

    await store.updateUiLoginAccessToken(newAccess, forEpoch: startEpoch);
    if (store.identityChanging || store.serverEpoch != startEpoch) {
      return RefreshOutcome.transientFailure(
        StateError('Credentials changed during refresh'),
      );
    }
    return RefreshOutcome.success(newAccess);
  }

  /// Speculatively refresh the ui_login access token if it's within
  /// [leadTime] of expiry. Returns `null` when no refresh was needed
  /// or when the current auth mode isn't ui_login. Called by the
  /// per-image Reload button and the app-resume lifecycle hook.
  ///
  /// R2-7: Explicit auth-mode gate. A stale `uiAccessTokenExpiresAt`
  /// (defensive — `clearUiLoginTokens` should null it) must not trip a
  /// ui-login refresh while the user is actually on basic/simple.
  Future<RefreshOutcome?> refreshUiAccessTokenIfDue({
    required GraphQLClient gqlClient,
    Duration leadTime = proactiveRefreshLead,
    String trigger = 'other',
  }) async {
    if ((ref.read(authTypeKeyProvider) ?? DBKeys.authType.initial) !=
        AuthType.uiLogin) {
      return null;
    }
    final expiresAt = ref
        .read(authCredentialsStoreProvider)
        .value
        ?.uiAccessTokenExpiresAt;
    if (expiresAt == null) return null;
    final remaining = expiresAt.difference(DateTime.now().toUtc());
    if (remaining > leadTime) return null;
    return refreshUiAccessToken(gqlClient: gqlClient, trigger: trigger);
  }

  /// Runs the appropriate verify-only round-trip and returns a typed
  /// [TestConnectionResult]. **Does not persist credentials** — caller
  /// must call [loginSimple] / [loginUi] explicitly to commit. This way
  /// hitting Test → Cancel leaves prior config untouched.
  Future<TestConnectionResult> testConnection({
    required AuthType authType,
    required String serverBaseUrl,
    required String username,
    required String password,
    required GraphQLClient Function() makeGqlClient,
  }) async {
    try {
      if (authType == AuthType.simpleLogin) {
        await verifySimpleCredentials(
          serverBaseUrl: serverBaseUrl,
          username: username,
          password: password,
        );
      } else if (authType == AuthType.uiLogin) {
        await verifyUiCredentials(
          gqlClient: makeGqlClient(),
          username: username,
          password: password,
        );
      } else if (authType == AuthType.basic) {
        // basic_auth has no login round-trip — verify by probing WITH the
        // Basic header (mirrors onboarding). First confirm it's really a
        // Suwayomi server, then confirm the credentials actually authorise the
        // @RequireAuth surface (which also fails when the server isn't on
        // basic_auth, i.e. wrong mode).
        final client = http.Client();
        try {
          final extra = ref.read(customHttpHeadersProvider).value;
          final isSuwayomi = await basicAuthConfirms(
            serverBaseUrl,
            client: client,
            username: username,
            password: password,
            extraHeaders: extra,
          );
          if (!isSuwayomi) {
            return const TestConnectionFailure(
              TestConnectionFailureKind.network,
              'no Suwayomi server reachable with those Basic credentials',
            );
          }
          final authorized = await authProbeAuthorized(
            serverBaseUrl,
            client: client,
            basic: '$username:$password',
            extraHeaders: extra,
          );
          if (!authorized) {
            return const TestConnectionFailure(
              TestConnectionFailureKind.invalidCredentials,
              'Basic credentials were rejected',
            );
          }
        } finally {
          client.close();
        }
      } else {
        return const TestConnectionFailure(
          TestConnectionFailureKind.unexpectedShape,
          'testConnection only supports basic, simpleLogin or uiLogin',
        );
      }
    } catch (e) {
      return classifyAuthError(e);
    }
    return const TestConnectionSuccess();
  }
}
