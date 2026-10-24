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
import '../../../graphql/__generated__/schema.graphql.dart'
    show Input$LoginInput, Input$RefreshTokenInput;
import '../../../utils/crash/diagnostics.dart';
import '../../../utils/platform/web_auth_mode.dart';
import '../../account/data/account_notice.dart';
import '../../account/data/account_session_repository.dart';
import '../../account/domain/account_binding.dart';
import '../../offline/data/offline_server_identity_repository.dart';
import '../../onboarding/data/server_resolver.dart'
    show authProbeAuthorized, authProbeExplicitlyRejects, basicAuthConfirms;
import '../../settings/presentation/general/timeout_settings/timeout_settings_section.dart';
import '../../settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import 'auth_credentials_store.dart';
import 'auth_state.dart';
import 'basic_credentials_rejected.dart';
import 'custom_headers_store.dart';
import 'graphql/__generated__/auth.graphql.dart';
import 'jwt_utils.dart';
import 'simple_login_client.dart';
import 'ui_login_token_rejected.dart';

part 'auth_coordinator.g.dart';

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
  webUnsupportedAuthMode,
}

/// Checks TLS errors before generic network errors, whose text overlaps.
TestConnectionFailure classifyAuthError(Object e) {
  if (e is UiLoginTokenRejected) {
    return const TestConnectionFailure(
      TestConnectionFailureKind.webUnsupportedAuthMode,
    );
  }
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
      // Suwayomi credential rejections need not contain "unauthorized".
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

/// An expired token cannot be sent; preserves the refresh cause for reachability handling.
class AccessTokenUnavailable extends ServerException {
  AccessTokenUnavailable(this.outcome)
    : super(
        originalException: switch (outcome) {
          RefreshTransientFailure(:final error) => _rootCause(error),
          _ => StateError('Session expired'),
        },
      );

  final RefreshOutcome outcome;

  static Object _rootCause(Object error) {
    final link = error is OperationException ? error.linkException : error;
    if (link is ServerException && link.originalException != null) {
      return link.originalException!;
    }
    return link ?? error;
  }

  @override
  String toString() =>
      'AccessTokenUnavailable(${describeRefreshOutcome(outcome)})';
}

/// Token-free refresh diagnostic; null means no refresh was due.
String describeRefreshOutcome(RefreshOutcome? outcome, {DateTime? now}) =>
    switch (outcome) {
      null => 'outcome=not-due',
      RefreshSuccess(:final newAccessToken) =>
        'outcome=success ${describeTokenExpiry(newAccessToken, now: now)}',
      RefreshAuthFailure() => 'outcome=auth-failure',
      RefreshTransientFailure(:final error) =>
        'outcome=transient cause=${describeDiagnosticError(error)}',
    };

/// Reports token expiry without logging the token itself.
String describeTokenExpiry(String? token, {DateTime? now}) {
  if (token == null || token.isEmpty) return 'token=none';
  final exp = decodeJwtExp(token);
  if (exp == null) return 'exp=unknown';
  return 'expIn=${exp.difference(now ?? DateTime.now().toUtc()).inSeconds}s';
}

/// Caps diagnostics at the error's first line to avoid logging entire server stack traces.
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

// Only HTTP-layer link exceptions expose status codes for auth-failure classification.
int? _httpStatusOfLinkException(LinkException ex) {
  if (ex is HttpLinkServerException) {
    return ex.response.statusCode;
  }
  return null;
}

/// Refreshes proactively because image requests bypass the GraphQL auth link.
@Riverpod(keepAlive: true)
class AuthCoordinator extends _$AuthCoordinator {
  /// Refresh lead covers network round-trip and reader prefetch latency.
  static const Duration proactiveRefreshLead = Duration(seconds: 60);

  // Cap timers for tokens with far-future expiry claims.
  static const Duration _maxProactiveDelay = Duration(hours: 24);

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
    } catch (e, st) {
      debugPrint('proactive refresh callback raised: $e\n$st');
      _scheduleBackoffRefresh();
    }
  }

  void _cancelProactiveRefresh() {
    _proactiveRefreshTimer?.cancel();
    _proactiveRefreshTimer = null;
    _proactiveBackoffStep = 0;
  }

  @visibleForTesting
  bool get debugHasProactiveTimer => _proactiveRefreshTimer != null;


  /// Returns a verified cookie without persisting it; the server still creates a session.
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

  /// Returns verified tokens without persisting them; throws on failure.
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


  /// Probes Basic credentials before persisting; Basic auth has no login round-trip.
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
      ref.read(needsReauthProvider.notifier).set(false);
    }, expectedEpoch: store.serverEpoch);
  }

  Future<void> loginSimple({
    required String serverBaseUrl,
    required String username,
    required String password,
  }) async {
    final store = ref.read(authCredentialsStoreProvider.notifier);
    // Capture the epoch before verification so a switch cannot persist credentials for another host.
    await store.withIdentityChange(() async {
      final epoch = store.serverEpoch;
      final cookie = await verifySimpleCredentials(
        serverBaseUrl: serverBaseUrl,
        username: username,
        password: password,
      );
      await store.saveSimpleLoginCookie(cookie, forEpoch: epoch);
      ref.read(needsReauthProvider.notifier).set(false);
    }, expectedEpoch: store.serverEpoch);
  }

  /// Persists verified tokens; the password is never stored.
  Future<void> loginUi({
    required GraphQLClient gqlClient,
    required String username,
    required String password,
    String? serverBaseUrl,
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
      // A Simple-login server answers the login mutation yet rejects its token.
      if (serverBaseUrl != null && ref.read(isWebProvider)) {
        final probe = http.Client();
        try {
          if (await authProbeExplicitlyRejects(
            serverBaseUrl,
            client: probe,
            bearer: tokens.accessToken,
            extraHeaders: ref.read(customHttpHeadersProvider).value,
          )) {
            throw const UiLoginTokenRejected();
          }
        } finally {
          probe.close();
        }
      }
      await adoptUiLoginTokens(
        gqlClient: gqlClient,
        tokens: tokens,
        forEpoch: epoch,
        address: address,
        username: username,
      );
    }, expectedEpoch: store.serverEpoch);
  }

  Future<void> adoptUiLoginTokens({
    required GraphQLClient gqlClient,
    required UiLoginTokens tokens,
    required int forEpoch,
    required String address,
    required String username,
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
      // Bind to userId and catalogId; LAN/remote handovers can change the address.
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
      await ref.read(accountNoticeProvider.notifier).set(null);
      ref.read(needsReauthProvider.notifier).set(false);
    }, expectedEpoch: forEpoch);
  }

  Future<RefreshOutcome> refreshUiAccessToken({
    required GraphQLClient gqlClient,
    String trigger = 'other',
  }) async {
    final store = ref.read(authCredentialsStoreProvider.notifier);
    // Joining a refresh inside an identity change could wait on that same change.
    if (store.insideIdentityChange) {
      recordDiagnostic(
        '[${DateTime.now().toIso8601String()}] auth-refresh: '
        'trigger=$trigger refused=inside-identity-change\n',
      );
      return _refreshUiAccessTokenImpl(gqlClient);
    }
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
      final outcome = await _refreshAcrossHandover(store, gqlClient);
      recordDiagnostic(
        '[${DateTime.now().toIso8601String()}] auth-refresh: '
        'trigger=$trigger ${describeRefreshOutcome(outcome)}\n',
      );
      completer.complete(outcome);
      return outcome;
    } catch (e, st) {
      // Unexpected throws are transient; only confirmed auth failures may clear tokens.
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

  static const Duration _handoverSettleTimeout = Duration(seconds: 10);

  // Retry once through the new client after an endpoint handover; never retry a sign-in change.
  Future<RefreshOutcome> _refreshAcrossHandover(
    AuthCredentialsStore store,
    GraphQLClient gqlClient,
  ) async {
    final session = store.sessionEpoch;
    final handovers = store.handovers;
    final outcome = await _refreshUiAccessTokenImpl(gqlClient);
    if (outcome is! RefreshTransientFailure) return outcome;
    final handedOver =
        store.handovers != handovers ||
        (store.identityChanging && !store.sessionChanging);
    if (!handedOver || store.sessionEpoch != session) return outcome;
    if (!await store.identitySettled(timeout: _handoverSettleTimeout) ||
        !ref.mounted ||
        store.sessionEpoch != session ||
        !store.sessionAdmitted) {
      return outcome;
    }
    return _refreshUiAccessTokenImpl(
      ref.read(unauthenticatedGraphQlClientProvider),
    );
  }

  Future<RefreshOutcome> _refreshUiAccessTokenImpl(
    GraphQLClient gqlClient,
  ) async {
    final store = ref.read(authCredentialsStoreProvider.notifier);
    final startEpoch = store.serverEpoch;
    if (store.identityChanging || !store.sessionAdmitted) {
      return RefreshOutcome.transientFailure(
        StateError('Credentials are changing'),
      );
    }
    // Wait for hydration before treating missing in-memory tokens as a dead session.
    final storeState = ref.read(authCredentialsStoreProvider);
    if (storeState.value == null) {
      // Retry failed hydration so refresh backoff can make progress.
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
      // Network failures do not invalidate the stored refresh token.
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
      // Refresh rejection can arrive as HTTP 401/403, not only as GraphQL errors.
      final link = exception.linkException;
      if (link != null) {
        final status = _httpStatusOfLinkException(link);
        if (status == 401 || status == 403) {
          await store.clearUiLoginTokens(forEpoch: startEpoch);
          if (store.identityChanging || store.serverEpoch != startEpoch) {
            return RefreshOutcome.transientFailure(
              StateError('Credentials changed during refresh'),
            );
          }
          ref.read(needsReauthProvider.notifier).set(true);
          return const RefreshOutcome.authFailure();
        }
        return RefreshOutcome.transientFailure(exception);
      }
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
      await store.clearUiLoginTokens(forEpoch: startEpoch);
      if (store.identityChanging || store.serverEpoch != startEpoch) {
        return RefreshOutcome.transientFailure(
          StateError('Credentials changed during refresh'),
        );
      }
      ref.read(needsReauthProvider.notifier).set(true);
      return const RefreshOutcome.authFailure();
    }

    // Recheck the mode after awaiting refresh so a mode change cannot resurrect UI Login tokens.
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

  /// Refreshes within [leadTime] of expiry; null means no refresh was due or UI Login is inactive.
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

  /// Returns a usable UI Login token or null when absent or inactive.
  /// A failed refresh may use a still-valid token; expired tokens get one retry, then throw [AccessTokenUnavailable].
  /// Handover-spawned requests wait for the new endpoint; other identity changes refuse refresh.
  Future<String?> usableUiAccessToken({
    required GraphQLClient Function() gqlClient,
    required String trigger,
  }) async {
    if ((ref.read(authTypeKeyProvider) ?? DBKeys.authType.initial) !=
        AuthType.uiLogin) {
      return null;
    }
    final store = ref.read(authCredentialsStoreProvider.notifier);
    final state = await ref.read(authCredentialsStoreProvider.future);
    final token = state.uiAccessToken;
    if (token == null || token.isEmpty) return null;
    if (!_expiresWithin(state.uiAccessTokenExpiresAt, proactiveRefreshLead)) {
      return token;
    }

    // Other identity changes may be awaiting this request, so they cannot wait for refresh.
    final handover = store.insideHandover;
    final refusing = store.insideIdentityChange && !handover;
    Future<RefreshOutcome> refresh() {
      Future<RefreshOutcome> run() =>
          refreshUiAccessToken(gqlClient: gqlClient(), trigger: trigger);
      return handover ? store.outsideIdentityChange(run) : run();
    }

    String? stillValid() {
      final current = ref.read(authCredentialsStoreProvider).value;
      final access = current?.uiAccessToken;
      if (access == null || access.isEmpty) return null;
      return _expiresWithin(current?.uiAccessTokenExpiresAt, Duration.zero)
          ? null
          : access;
    }

    var outcome = await refresh();
    if (outcome is RefreshSuccess) return outcome.newAccessToken;
    var valid = stillValid();
    if (valid != null) return valid;
    // A waking network may succeed immediately after its first connection times out.
    if (outcome is RefreshTransientFailure && !refusing) {
      outcome = await refresh();
      if (outcome is RefreshSuccess) return outcome.newAccessToken;
      valid = stillValid();
      if (valid != null) return valid;
    }
    recordDiagnostic(
      '[${DateTime.now().toIso8601String()}] auth-gate: trigger=$trigger '
      'blocked ${describeTokenExpiry(token)} '
      '${describeRefreshOutcome(outcome)}\n',
    );
    throw AccessTokenUnavailable(outcome);
  }

  // Unknown expiry counts as live because no proactive refresh can be scheduled.
  static bool _expiresWithin(DateTime? expiresAt, Duration lead) =>
      expiresAt != null && expiresAt.difference(DateTime.now().toUtc()) <= lead;

  /// Tests credentials without persisting them.
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
        // Basic auth has no login round-trip; probe both server identity and protected access.
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
