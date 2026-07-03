// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:queue/queue.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/db_keys.dart';
import '../constants/timeout_constants.dart';
import '../constants/endpoints.dart';
import '../constants/enum.dart';
import '../features/auth/data/auth_coordinator.dart';
import '../features/auth/data/auth_credentials_store.dart';
import '../features/auth/data/auth_state.dart';
import '../features/auth/data/suwayomi_auth_link.dart';
import '../features/settings/presentation/general/timeout_settings/timeout_settings_section.dart';
import '../features/settings/presentation/server/widget/client/server_port_tile/server_port_tile.dart';
import '../features/settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import '../features/settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import '../utils/extensions/custom_extensions.dart';
import '../utils/logger/logger_link.dart';
import '../utils/mixin/shared_preferences_client_mixin.dart';
import '../utils/network/timeout_http_client.dart';

part 'global_providers.g.dart';

@riverpod
GraphQLClient graphQlClient(Ref ref) {
  final authType = ref.watch(authTypeKeyProvider) ?? DBKeys.authType.initial;
  final credentials = ref.watch(credentialsProvider).valueOrNull;

  // Timeout settings
  final timeoutMs = ref.watch(serverRequestTimeoutProvider) ??
      DBKeys.serverRequestTimeout.initial as int;
  final autoRetry = ref.watch(autoRefreshOnTimeoutProvider).ifNull();
  final retryDelayMs = ref.watch(autoRefreshRetryDelayProvider) ??
      DBKeys.autoRefreshRetryDelay.initial as int;

  // Every attempt gets the FULL timeout. Subdividing the budget into
  // delay-sized attempts (the old model) rapid-fires aborts while the server
  // keeps fetching each one from the source; the stacked fetches have been
  // observed to drive a server to 2GB RAM / 70% CPU. Few, full-length
  // attempts keep retry pressure bounded.
  final effectiveTimeoutMs = timeoutMs;
  final retryCount = autoRetry ? TimeoutConstants.autoRefreshMaxRetries : 0;

  Link link = HttpLink(
    Endpoints.baseApi(
      baseUrl: ref.watch(serverUrlProvider) ?? DBKeys.serverUrl.initial,
      port: ref.watch(serverPortProvider),
      addPort: ref.watch(serverPortToggleProvider).ifNull(),
      isGraphQl: true,
    ),
    followRedirects: true,
    // httpResponseDecoder: httpResponseDecoder,
    defaultHeaders: {'Content-Type': 'application/json; charset=utf-8'},
    httpClient: TimeoutHttpClient(
      Duration(milliseconds: effectiveTimeoutMs),
      retries: retryCount,
      retryDelay: Duration(milliseconds: retryDelayMs),
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
        final snapshot =
            await ref.read(authCredentialsStoreProvider.future);
        return authType == AuthType.simpleLogin
            ? snapshot.simpleLoginCookieHeader
            : snapshot.uiAuthorizationHeader;
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
          link: HttpLink(Endpoints.baseApi(
            baseUrl: ref.read(serverUrlProvider) ?? DBKeys.serverUrl.initial,
            port: ref.read(serverPortProvider),
            addPort: ref.read(serverPortToggleProvider).ifNull(),
            isGraphQl: true,
          )),
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
            timeoutMs * (retryCount + 1) + retryDelayMs * retryCount + 2000),
    cache: GraphQLCache(store: ref.watch(hiveStoreProvider)),
  );
}

@riverpod
GraphQLClient graphQlSubscriptionClient(Ref ref) {
  final authType = ref.watch(authTypeKeyProvider) ?? DBKeys.authType.initial;
  final credentials = ref.watch(credentialsProvider).valueOrNull;
  // Watch ONLY the socket-relevant auth material (cookie + token raw strings)
  // so this client is rebuilt — and the socket reconnects with fresh auth — on
  // a re-login or token/cookie refresh. Reading it once (the old behaviour) left
  // the connection pinned to the auth captured at first connect, so after a
  // refresh the @requireAuth subscriptions (downloads + library-update feeds)
  // silently died. Selecting the two raw strings (not the whole credentials
  // object) avoids tearing the socket down on unrelated writes — e.g. a login
  // also writes the saved password, which would otherwise reconnect twice.
  final socketAuth = ref.watch(authCredentialsStoreProvider.select(
    (s) => (
      cookie: s.valueOrNull?.simpleLoginCookie,
      token: s.valueOrNull?.uiAccessToken,
    ),
  ));
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
    final cookie = socketAuth.cookie;
    handshakeHeaders =
        (cookie == null || cookie.isEmpty) ? null : {'Cookie': cookie};
  } else if (authType == AuthType.basic && credentials.isNotBlank) {
    handshakeHeaders = {'Authorization': credentials!};
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
  final timeoutMs = ref.watch(serverRequestTimeoutProvider) ??
      DBKeys.serverRequestTimeout.initial as int;
  return GraphQLClient(
    link: loggerLink.concat(wsLink),
    defaultPolicies: DefaultPolicies(
      query: Policies(fetch: FetchPolicy.noCache),
    ),
    // Same package-level timeout as the query client (default is a hard 5s).
    queryRequestTimeout: Duration(milliseconds: timeoutMs + 2000),
    cache: GraphQLCache(store: ref.watch(hiveStoreProvider)),
  );
}

@riverpod
ValueNotifier<GraphQLClient> graphQlClientNotifier(Ref ref) {
  final notifier = ValueNotifier(ref.watch(graphQlClientProvider));
  // Dispose of the notifier when the provider is destroyed
  ref.onDispose(notifier.dispose);

  // Notify listeners of this provider whenever the ValueNotifier updates.
  notifier.addListener(ref.notifyListeners);

  return notifier;
}

@riverpod
class AuthTypeKey extends _$AuthTypeKey
    with SharedPreferenceEnumClientMixin<AuthType> {
  @override
  AuthType? build() => initialize(
        DBKeys.authType,
        enumList: AuthType.values,
      );
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
  Locale? build() => initialize(
        DBKeys.l10n,
        fromJson: fromJson,
        toJson: toJson,
      );
}

@riverpod
SharedPreferences sharedPreferences(ref) => throw UnimplementedError();

@riverpod
HiveStore hiveStore(Ref ref) => throw UnimplementedError();

@riverpod
Queue rateLimitQueue(Ref ref, [String? query]) {
  final queue = Queue(
    parallel: 3,
    delay: const Duration(milliseconds: 500),
  );
  ref.onDispose(() {
    queue.cancel();
  });
  return queue;
}
