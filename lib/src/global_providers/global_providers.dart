// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
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
import '../features/auth/data/auth_state.dart';
import '../features/auth/data/custom_headers_store.dart';
import '../features/auth/data/suwayomi_auth_link.dart';
import '../features/offline/data/server_reachability.dart';
import '../features/settings/presentation/general/timeout_settings/timeout_settings_section.dart';
import '../features/settings/presentation/server/widget/client/server_port_tile/server_port_tile.dart';
import '../features/settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import '../features/settings/presentation/server/widget/credential_popup/credentials_popup.dart';
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

// keepAlive: the reader captures this client (and its ref) once and issues
// progress writes through it. Under autoDispose the ref could die mid-write
// during provider churn, throwing a disposed-ref StateError inside
// SuwayomiAuthLink.getHeaders — the silent online-progress-loss root cause.
@Riverpod(keepAlive: true)
GraphQLClient graphQlClient(Ref ref) {
  final authType = ref.watch(authTypeKeyProvider) ?? DBKeys.authType.initial;
  final credentials = ref.watch(credentialsProvider).value;

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
  final customHeaders = ref.watch(customHttpHeadersProvider);

  Link link = HttpLink(
    Endpoints.baseApi(
      baseUrl: ref.watch(serverUrlProvider) ?? DBKeys.serverUrl.initial,
      port: ref.watch(serverPortProvider),
      addPort: ref.watch(serverPortToggleProvider).ifNull(),
      isGraphQl: true,
    ),
    followRedirects: true,
    httpResponseDecoder: tsumiruHttpResponseDecoder,
    defaultHeaders: applyCustomHeaders(
      {'Content-Type': 'application/json; charset=utf-8'},
      customHeaders,
    ),
    httpClient: TimeoutHttpClient(
      Duration(milliseconds: effectiveTimeoutMs),
      retries: retryCount,
      retryDelay: Duration(milliseconds: retryDelayMs),
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

  // Basic authentication link (unchanged).
  if (authType == AuthType.basic && credentials.isNotBlank) {
    final AuthLink authLink = AuthLink(getToken: () => credentials);
    link = authLink.concat(link);
  }

  // simple_login / ui_login link.
  if (authType == AuthType.simpleLogin || authType == AuthType.uiLogin) {
    final suwayomiAuthLink = SuwayomiAuthLink(
      authType: () => authType,
      getHeaders: () async {
        // Synchronously read the cached snapshot — populated at startup
        // by the eager `await container.read(...future)` in main(). We
        // read via `.future` defensively in case a caller invokes a
        // GraphQL operation before the preload finishes.
        final snapshot = await ref.read(authCredentialsStoreProvider.future);
        final base = authType == AuthType.simpleLogin
            ? snapshot.simpleLoginCookieHeader
            : snapshot.uiAuthorizationHeader;
        final custom = ref.read(customHttpHeadersProvider);
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
              ref.read(customHttpHeadersProvider),
            ),
          ),
          queryRequestTimeout: Duration(milliseconds: timeoutMs + 2000),
          cache: GraphQLCache(),
        );
        return await ref
            .read(authCoordinatorProvider.notifier)
            .refreshUiAccessToken(gqlClient: rawClient);
      },
      onNeedsReauth: () {
        ref.read(needsReauthProvider.notifier).set(true);
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
                ref.read(serverUnreachableProvider.notifier).set(false);
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
                ref.read(serverUnreachableProvider.notifier).set(true);
              } catch (_) {}
            });
          }
          throw error;
        });
  });
  link = reachabilityLink.concat(link);

  final loggerLink = LoggerLink();
  return GraphQLClient(
    link: loggerLink.concat(link),
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
@Riverpod(keepAlive: true)
GraphQLClient graphQlSubscriptionClient(Ref ref) {
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
  // so it leaves the connection unauthenticated and any @requireAuth
  // subscription (e.g. downloadStatusChanged) fails with "Unauthorized" —
  // while auth-exempt subscriptions (updateStatusChanged) still work, which
  // is what made this look downloads-specific.
  //
  // graphql-transport-ws carries auth two ways, matching Suwayomi-Server:
  //   * ui_login  -> connection_init payload `{Authorization: <bare token>}`
  //                  (server `onInit` does NOT strip "Bearer "; the WebUI
  //                  sends the bare token, so we do too).
  //   * simple_login / basic -> the WS handshake (upgrade) headers.
  dynamic initialPayload;
  Map<String, String>? handshakeHeaders;
  if (authType == AuthType.uiLogin) {
    initialPayload = () async {
      final snapshot = await ref.read(authCredentialsStoreProvider.future);
      final token = snapshot.uiAccessToken;
      return (token == null || token.isEmpty)
          ? <String, dynamic>{}
          : <String, dynamic>{'Authorization': token};
    };
  } else if (authType == AuthType.simpleLogin) {
    final cookie = socketCookie;
    handshakeHeaders = (cookie == null || cookie.isEmpty)
        ? null
        : {'Cookie': cookie};
  } else if (authType == AuthType.basic && credentials.isNotBlank) {
    handshakeHeaders = {'Authorization': credentials!};
  }
  // Custom headers (e.g. Cloudflare Zero Trust) also guard the WS upgrade.
  final customWsHeaders = ref.watch(customHttpHeadersProvider);
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
    link: loggerLink.concat(wsLink),
    defaultPolicies: DefaultPolicies(
      query: Policies(fetch: FetchPolicy.noCache),
    ),
    // Same package-level timeout as the query client (default is a hard 5s).
    queryRequestTimeout: Duration(milliseconds: timeoutMs + 2000),
    // In-memory only, matching the query client.
    cache: GraphQLCache(store: InMemoryStore()),
  );
}

// Named "holder" so its generated provider can't collide with
// graphQlClientProvider: riverpod_generator 4 strips a trailing "Notifier"
// from provider names, which made the old graphQlClientNotifier fold into
// the same name as the client provider above.
@riverpod
ValueNotifier<GraphQLClient> graphQlClientHolder(Ref ref) {
  final notifier = ValueNotifier(ref.watch(graphQlClientProvider));
  ref.onDispose(notifier.dispose);

  notifier.addListener(ref.notifyListeners);

  return notifier;
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
