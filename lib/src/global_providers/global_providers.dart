// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:queue/queue.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/db_keys.dart';
import '../constants/endpoints.dart';
import '../constants/enum.dart';
import '../constants/timeout_constants.dart';
import '../features/auth/data/auth_coordinator.dart';
import '../features/auth/data/auth_credentials_store.dart';
import '../features/auth/data/auth_session_status.dart';
import '../features/auth/data/auth_state.dart';
import '../features/auth/data/custom_headers_store.dart';
import '../features/auth/data/jwt_utils.dart';
import '../features/auth/data/suwayomi_auth_link.dart';
import '../features/offline/data/server_reachability.dart';
import '../features/settings/presentation/general/timeout_settings/timeout_settings_section.dart';
import '../features/settings/presentation/server/widget/client/server_port_tile/server_port_tile.dart';
import '../features/settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import '../features/settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import '../utils/crash/diagnostics.dart';
import '../utils/extensions/custom_extensions.dart';
import '../utils/logger/logger_link.dart';
import '../utils/mixin/shared_preferences_client_mixin.dart';
import '../utils/network/graphql_errors.dart';
import '../utils/network/timeout_http_client.dart';

part 'global_providers.g.dart';

/// A request that may have reached the server must never be replayed after a
/// handover: mutations could otherwise run twice. GraphQL reads are safe to
/// send once to the newly-selected endpoint.
bool _isGraphQlRead(http.BaseRequest request) {
  if (request is! http.Request) return false;
  try {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final document = body['query'] as String?;
    if (document == null) return false;
    return !RegExp(r'^\s*(mutation|subscription)\b').hasMatch(document);
  } catch (_) {
    return false;
  }
}

final unauthenticatedGraphQlClientProvider = Provider<GraphQLClient>((ref) {
  final timeoutMs =
      ref.watch(serverRequestTimeoutProvider) ??
      DBKeys.serverRequestTimeout.initial as int;
  final client = TimeoutHttpClient(Duration(milliseconds: timeoutMs));
  ref.onDispose(client.close);
  return GraphQLClient(
    link: HttpLink(
      Endpoints.baseApi(
        baseUrl: ref.watch(serverUrlProvider) ?? DBKeys.serverUrl.initial,
        port: ref.watch(serverPortProvider),
        addPort: ref.watch(serverPortToggleProvider).ifNull(),
        isGraphQl: true,
      ),
      httpClient: client,
      httpResponseDecoder: tsumiruHttpResponseDecoder,
      defaultHeaders: applyCustomHeaders(
        {},
        ref.watch(customHttpHeadersProvider).value,
      ),
    ),
    queryRequestTimeout: Duration(milliseconds: timeoutMs + 2000),
    cache: GraphQLCache(),
    defaultPolicies: DefaultPolicies(
      query: Policies(fetch: FetchPolicy.noCache),
    ),
  );
});

Link _sessionLink(bool Function() isCurrentSession) => Link.function((
  request, [
  forward,
]) async* {
  if (!isCurrentSession()) throw StateError('Authentication session changed');
  await for (final response in forward!(request)) {
    if (!isCurrentSession()) throw StateError('Authentication session changed');
    yield response;
  }
});

@Riverpod(keepAlive: true)
GraphQLClient graphQlClient(Ref ref) {
  final isCurrentSession = watchAuthSession(ref);
  final authType = ref.watch(authTypeKeyProvider) ?? DBKeys.authType.initial;
  // Watched so a credential change still rebuilds the client and drops cached
  // results; the value itself is read per request, below.
  ref.watch(credentialsProvider);

  // Timeout settings
  final timeoutMs =
      ref.watch(serverRequestTimeoutProvider) ??
      DBKeys.serverRequestTimeout.initial as int;
  final autoRetry = ref.watch(autoRefreshOnTimeoutProvider).ifNull();
  final retryDelayMs =
      ref.watch(autoRefreshRetryDelayProvider) ??
      DBKeys.autoRefreshRetryDelay.initial as int;

  // Every attempt gets the FULL timeout. Subdividing the budget into
  // delay-sized attempts (the old model) rapid-fires aborts while the server
  // keeps fetching each one from the source; the stacked fetches have been
  // observed to drive a server to 2GB RAM / 70% CPU. Few, full-length
  // attempts keep retry pressure bounded.
  final effectiveTimeoutMs = timeoutMs;
  final retryCount = autoRetry ? TimeoutConstants.autoRefreshMaxRetries : 0;

  // Generic custom headers (e.g. Cloudflare Zero Trust service tokens) sent
  // with every Suwayomi-server request. Watching here rebuilds the client
  // when they change.
  final customHeaders = ref.watch(customHttpHeadersProvider).value ?? const {};

  Link link = HttpLink(
    Endpoints.baseApi(
      baseUrl: ref.watch(serverUrlProvider) ?? DBKeys.serverUrl.initial,
      port: ref.watch(serverPortProvider),
      addPort: ref.watch(serverPortToggleProvider).ifNull(),
      isGraphQl: true,
    ),
    followRedirects: true,
    httpResponseDecoder: tsumiruHttpResponseDecoder,
    defaultHeaders: applyCustomHeaders({
      'Content-Type': 'application/json; charset=utf-8',
    }, customHeaders),
    httpClient: TimeoutHttpClient(
      Duration(milliseconds: effectiveTimeoutMs),
      retries: retryCount,
      retryDelay: Duration(milliseconds: retryDelayMs),
      isCurrentSession: isCurrentSession,
      onConnectionFailure: (request) async {
        if (!_isGraphQlRead(request)) return null;
        await ref.read(serverEndpointResolverProvider.notifier).refresh();
        return Uri.parse(
          Endpoints.baseApi(
            baseUrl: ref.read(serverUrlProvider) ?? DBKeys.serverUrl.initial,
            port: ref.read(serverPortProvider),
            addPort: ref.read(serverPortToggleProvider).ifNull(),
            isGraphQl: true,
          ),
        );
      },
    ),
  );

  // Auto retry is handled by TimeoutHttpClient retries instead of RetryLink

  // Basic authentication link.
  //
  // Reads the credential per request rather than capturing whatever the
  // snapshot held when the client was built: secure storage resolves
  // asynchronously, so a client built during that gap carried no
  // Authorization header and every early request came back 401 — briefly on a
  // good launch, and until something happened to rebuild the client after a
  // fresh sign-in. The ui/simple links already await their credentials the
  // same way.
  if (authType == AuthType.basic) {
    final AuthLink authLink = AuthLink(
      getToken: () async {
        final stored = await ref.read(credentialsProvider.future);
        return stored.isNotBlank ? stored : null;
      },
    );
    link = authLink.concat(link);
  }

  // simple_login / ui_login link.
  if (authType == AuthType.simpleLogin || authType == AuthType.uiLogin) {
    final suwayomiAuthLink = SuwayomiAuthLink(
      isCurrentSession: isCurrentSession,
      authType: () => authType,
      getHeaders: () async {
        // A token already known to be expired (or about to be) is refreshed
        // before the request instead of after its 401: at launch after a
        // pause, every early request otherwise went out, was rejected, and
        // waited on the same refresh to be retried. Refreshing early costs
        // nothing (the refresh token isn't rotated) and joins any refresh
        // already in flight. A failed one sends the current token, as before.
        if (authType == AuthType.uiLogin) {
          try {
            await ref
                .read(authCoordinatorProvider.notifier)
                .refreshUiAccessTokenIfDue(
                  gqlClient: ref.read(unauthenticatedGraphQlClientProvider),
                  trigger: 'request-ahead',
                );
          } catch (_) {}
        }
        // Synchronously read the cached snapshot — populated at startup
        // by the eager `await container.read(...future)` in main(). We
        // read via `.future` defensively in case a caller invokes a
        // GraphQL operation before the preload finishes.
        final snapshot = await ref.read(authCredentialsStoreProvider.future);
        final base = authType == AuthType.simpleLogin
            ? snapshot.simpleLoginCookieHeader
            : snapshot.uiAuthorizationHeader;
        final custom = ref.read(customHttpHeadersProvider).value ?? const {};
        if (base == null) {
          return custom.isEmpty ? null : Map<String, String>.from(custom);
        }
        return applyCustomHeaders(Map<String, String>.from(base), custom);
      },
      refreshAccessToken: () async {
        // Refresh path only applies to ui_login. For simple_login the
        // Link short-circuits before invoking this callback, so any
        // value works; AuthFailure is the most semantically truthful.
        if (authType != AuthType.uiLogin) {
          return const RefreshAuthFailure();
        }
        // Use a NON-authed GraphQL client to avoid recursion: the refresh
        // mutation must NOT go through SuwayomiAuthLink itself. The
        // AuthCoordinator owns single-flight dedup (R2-3), so both Link
        // instances (query + subscription) share one refresh through it.
        final rawClient = GraphQLClient(
          link: HttpLink(
            Endpoints.baseApi(
              baseUrl: ref.read(serverUrlProvider) ?? DBKeys.serverUrl.initial,
              port: ref.read(serverPortProvider),
              addPort: ref.read(serverPortToggleProvider).ifNull(),
              isGraphQl: true,
            ),
            httpResponseDecoder: tsumiruHttpResponseDecoder,
            defaultHeaders: applyCustomHeaders(
              const {},
              ref.read(customHttpHeadersProvider).value,
            ),
          ),
          queryRequestTimeout: Duration(milliseconds: timeoutMs + 2000),
          cache: GraphQLCache(),
        );
        return await ref
            .read(authCoordinatorProvider.notifier)
            .refreshUiAccessToken(
              gqlClient: rawClient,
              trigger: 'auth-link',
            );
      },
      onNeedsReauth: () {
        if (ref.read(hasStoredCredentialsProvider)) {
          ref.read(needsReauthProvider.notifier).set(true);
        }
      },
    );
    link = suwayomiAuthLink.concat(link);
  }

  // Any successful server answer proves reachability. Without this the
  // offline latch only cleared on library refresh gestures, so one transient
  // blip could pin details/reader offline until the user happened to pull the
  // library. Deferred a tick: responses can arrive while a provider builds.
  final reachabilityLink = Link.function((request, [forward]) {
    return forward!(request)
        .map((response) {
          if (response.errors == null || response.errors!.isEmpty) {
            Future(() {
              try {
                ref
                    .read(serverUnreachableProvider.notifier)
                    .set(
                      false,
                      reason: 'op=${request.operation.operationName}',
                    );
              } catch (_) {}
            });
          }
          return response;
        })
        .handleError((Object error) {
          // The inverse. Only the downloader used to set this, so everything else
          // kept paying its own retries to discover the same thing.
          if (isConnectionError(error)) {
            Future(() {
              try {
                ref
                    .read(serverUnreachableProvider.notifier)
                    .set(
                      true,
                      reason:
                          'op=${request.operation.operationName} '
                          'error=${error.runtimeType}: $error',
                    );
              } catch (_) {}
            });
          }
          throw error;
        });
  });
  link = reachabilityLink.concat(link);

  final loggerLink = LoggerLink();
  return GraphQLClient(
    link: _sessionLink(isCurrentSession).concat(loggerLink).concat(link),
    defaultPolicies: DefaultPolicies(
      query: Policies(fetch: FetchPolicy.noCache),
    ),
    // The package layers its own query timeout (default 5s) on top of the
    // HTTP client's; without this the Server Request Timeout setting can't
    // reach past 5s ("TimeoutException ... No stream event"). Sized to cover
    // the HTTP layer's whole retry window plus 2s grace, so the HTTP layer
    // always resolves first and keeps its error semantics.
    queryRequestTimeout: Duration(
      milliseconds:
          timeoutMs * (retryCount + 1) + retryDelayMs * retryCount + 2000,
    ),
    // In-memory only: the default fetch policy is noCache, so a persisted
    // store is write-only bloat (its Hive box grew ~100 MB/week and its
    // whole-file load OOM-crashed startup).
    cache: GraphQLCache(store: InMemoryStore()),
  );
}

// keepAlive: autoDispose tied the websocket's life to whatever screen happened
// to be watching a subscription, so navigating tore the socket down and the
// next screen opened a fresh one. Measured against the server: 2 handshakes per
// 10 min idle, 53 while navigating.
/// The ui_login `connection_init` payload.
///
/// The server resolves the socket's user once, from this payload, and keeps
/// it for the connection's whole life: an expired access token makes the
/// socket a visitor, and every @RequireAuth subscription on it
/// (updateStatusChanged, downloadStatusChanged) then fails "Unauthorized"
/// until it reconnects. Access tokens last 5 minutes by default and the first
/// subscription starts at launch, before any HTTP call has refreshed the
/// stored one — so without [refreshIfDue] a session opened after a pause lost
/// its live updates (and the library re-read they trigger) entirely.
///
/// A failed refresh still sends the current token: blocking the connection
/// would only trade a visitor socket for none.
Future<Map<String, dynamic>> uiLoginSocketPayload({
  required bool Function() isCurrentSession,
  required Future<void> Function() refreshIfDue,
  required Future<String?> Function() readToken,
}) async {
  if (!isCurrentSession()) {
    _wsAuthLog('connect-init aborted=session-changed-before');
    throw StateError('Authentication session changed');
  }
  try {
    await refreshIfDue();
  } catch (e) {
    _wsAuthLog(
      'connect-refresh threw cause=${e.runtimeType}: '
      '${e.toString().split('\n').first}',
    );
  }
  final token = await readToken();
  if (!isCurrentSession()) {
    _wsAuthLog('connect-init aborted=session-changed-after');
    throw StateError('Authentication session changed');
  }
  _wsAuthLog('connect-init ${describeSocketToken(token)}');
  return (token == null || token.isEmpty)
      ? <String, dynamic>{}
      : <String, dynamic>{'Authorization': token};
}

/// `expIn=<s>` for the token a socket authenticates with (negative: the
/// server binds this socket as a visitor), `token=none` without one. Never
/// the token itself.
@visibleForTesting
String describeSocketToken(String? token, {DateTime? now}) {
  if (token == null || token.isEmpty) return 'token=none';
  final exp = decodeJwtExp(token);
  if (exp == null) return 'exp=unknown';
  return 'expIn=${exp.difference(now ?? DateTime.now().toUtc()).inSeconds}s';
}

/// Whether the server would bind a socket sending [token] to its user. A token
/// without a readable expiry counts as live: there's nothing to wait for.
@visibleForTesting
bool socketTokenIsLive(String? token, {DateTime? now}) {
  if (token == null || token.isEmpty) return false;
  final exp = decodeJwtExp(token);
  return exp == null || exp.isAfter(now ?? DateTime.now().toUtc());
}

/// The socket resolves its user once, at connect: these lines show what it
/// was bound with, so an "Unauthorized" subscription later in the session can
/// be traced to the connect that caused it.
void _wsAuthLog(String event) => recordDiagnostic(
      '[${DateTime.now().toIso8601String()}] ws-auth: $event\n',
    );

@Riverpod(keepAlive: true)
GraphQLClient graphQlSubscriptionClient(Ref ref) {
  final isCurrentSession = watchAuthSession(ref);
  final authType = ref.watch(authTypeKeyProvider) ?? DBKeys.authType.initial;
  final credentials = ref.watch(credentialsProvider).value;
  // Only the cookie: it's pinned into the handshake at build time. The
  // ui_login token is read per-connect in initialPayload, so watching it just
  // rebuilt the socket on every refresh and killed the live subscriptions.
  final socketCookie = ref.watch(
    authCredentialsStoreProvider.select((s) => s.value?.simpleLoginCookie),
  );
  final wsUrl = Endpoints.baseApi(
    baseUrl: ref.watch(serverUrlProvider) ?? DBKeys.serverUrl.initial,
    port: ref.watch(serverPortProvider),
    addPort: ref.watch(serverPortToggleProvider).ifNull(),
    isGraphQl: true,
    isWebsocket: true,
  );

  // Authenticate the SOCKET itself, not a per-operation Link. A header /
  // context Link (AuthLink / SuwayomiAuthLink) never reaches the WebSocket,
  // so it leaves the connection unauthenticated and every @RequireAuth
  // subscription (downloadStatusChanged, updateStatusChanged) fails with
  // "Unauthorized".
  //
  // graphql-transport-ws carries auth two ways, matching Suwayomi-Server:
  //   * ui_login  -> connection_init payload `{Authorization: <bare token>}`
  //                  (server `onInit` does NOT strip "Bearer "; the WebUI
  //                  sends the bare token, so we do too).
  //   * simple_login / basic -> the WS handshake (upgrade) headers.
  dynamic initialPayload;
  Map<String, String>? handshakeHeaders;
  // Whether this socket's latest connect sent no live token.
  var boundAsVisitor = false;
  if (authType == AuthType.uiLogin) {
    // This provider rebuilds at launch as async settings load, disposing the
    // socket it built — often while that socket's connect is still awaiting
    // the refresh. Its payload no longer matters then, but touching `ref`
    // would throw, so the callbacks check `ref.mounted` first.
    initialPayload = () => uiLoginSocketPayload(
      isCurrentSession: isCurrentSession,
      refreshIfDue: () async {
        if (!ref.mounted) {
          _wsAuthLog('connect-refresh skipped=provider-disposed');
          return;
        }
        // An endpoint handover rebuilds this socket from inside the handover's
        // zone, so the refresh would be refused on the spot instead of waiting
        // for the handover to finish. Nothing awaits a socket connect, so it
        // can't be the handover waiting on itself.
        final coordinator = ref.read(authCoordinatorProvider.notifier);
        final gql = ref.read(unauthenticatedGraphQlClientProvider);
        final outcome = await ref
            .read(authCredentialsStoreProvider.notifier)
            .outsideIdentityChange(
              () => coordinator.refreshUiAccessTokenIfDue(
                gqlClient: gql,
                trigger: 'socket-connect',
              ),
            );
        _wsAuthLog(
          'connect-refresh outcome=${switch (outcome) {
            null => 'not-due',
            RefreshSuccess() => 'success',
            RefreshAuthFailure() => 'auth-failure',
            RefreshTransientFailure(:final error) =>
              'transient cause=${error.runtimeType}: '
                  '${error.toString().split('\n').first}',
          }}',
        );
      },
      readToken: () async {
        if (!ref.mounted) {
          // Sends an empty payload: the server binds a visitor socket.
          _wsAuthLog('connect-token skipped=provider-disposed');
          return null;
        }
        final token = (await ref.read(
          authCredentialsStoreProvider.future,
        )).uiAccessToken;
        boundAsVisitor = !socketTokenIsLive(token);
        return token;
      },
    );
    // A socket bound as a visitor stays one until it reconnects, and nothing
    // made it reconnect: HTTP recovered with the next refresh, but live
    // updates stayed dead for the session. Rebuild it once a live token lands.
    // Only then: a token expiring on a socket already bound doesn't matter,
    // and rebuilding on every refresh would kill the subscriptions for nothing.
    ref.listen(
      authCredentialsStoreProvider.select((s) => s.value?.uiAccessToken),
      (_, token) {
        if (!boundAsVisitor || !socketTokenIsLive(token)) return;
        boundAsVisitor = false;
        _wsAuthLog('reconnect reason=visitor-bind');
        ref.invalidateSelf();
      },
    );
  } else if (authType == AuthType.simpleLogin) {
    final cookie = socketCookie;
    handshakeHeaders = (cookie == null || cookie.isEmpty)
        ? null
        : {'Cookie': cookie};
  } else if (authType == AuthType.basic && credentials.isNotBlank) {
    handshakeHeaders = {'Authorization': credentials!};
  }
  // Custom headers (e.g. Cloudflare Zero Trust) also guard the WS upgrade.
  final customWsHeaders =
      ref.watch(customHttpHeadersProvider).value ?? const {};
  if (customWsHeaders.isNotEmpty) {
    handshakeHeaders = applyCustomHeaders(
      Map<String, String>.from(handshakeHeaders ?? const {}),
      customWsHeaders,
    );
  }

  final wsLink = WebSocketLink(
    wsUrl,
    subProtocol: GraphQLProtocol.graphqlTransportWs,
    config: SocketClientConfig(
      initialPayload: initialPayload,
      headers: handshakeHeaders,
    ),
  );
  // Close the previous socket when this provider rebuilds (auth/url changed) or
  // is disposed, so a re-auth doesn't leak the old connection.
  ref.onDispose(() => unawaited(wsLink.dispose().catchError((_) {})));

  final loggerLink = LoggerLink();
  final timeoutMs =
      ref.watch(serverRequestTimeoutProvider) ??
      DBKeys.serverRequestTimeout.initial as int;
  return GraphQLClient(
    link: _sessionLink(isCurrentSession).concat(loggerLink).concat(wsLink),
    defaultPolicies: DefaultPolicies(
      query: Policies(fetch: FetchPolicy.noCache),
    ),
    // Same package-level timeout as the query client (default is a hard 5s).
    queryRequestTimeout: Duration(milliseconds: timeoutMs + 2000),
    // In-memory only, matching the query client.
    cache: GraphQLCache(store: InMemoryStore()),
  );
}

@riverpod
class AuthTypeKey extends _$AuthTypeKey
    with SharedPreferenceEnumClientMixin<AuthType> {
  @override
  AuthType? build() => initialize(DBKeys.authType, enumList: AuthType.values);
}

@riverpod
class L10n extends _$L10n with SharedPreferenceClientMixin<Locale> {
  Map<String, String> toJson(Locale locale) => {
    if (locale.countryCode.isNotBlank) "countryCode": locale.countryCode!,
    if (locale.languageCode.isNotBlank) "languageCode": locale.languageCode,
    if (locale.scriptCode.isNotBlank) "scriptCode": locale.scriptCode!,
  };
  Locale? fromJson(dynamic json) =>
      json is! Map<String, dynamic> || (json["languageCode"] == null)
      ? null
      : Locale.fromSubtags(
          languageCode: json["languageCode"]!.toString(),
          scriptCode: json["scriptCode"]?.toString(),
          countryCode: json["countryCode"]?.toString(),
        );
  @override
  Locale? build() =>
      initialize(DBKeys.l10n, fromJson: fromJson, toJson: toJson);
}

@riverpod
SharedPreferences sharedPreferences(Ref ref) => throw UnimplementedError();

@riverpod
Queue rateLimitQueue(Ref ref, [String? query]) {
  final queue = Queue(parallel: 3, delay: const Duration(milliseconds: 500));
  ref.onDispose(() {
    queue.cancel();
  });
  return queue;
}
