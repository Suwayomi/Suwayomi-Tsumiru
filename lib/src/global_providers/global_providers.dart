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
import '../features/auth/data/auth_recovery_target.dart';
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
import '../utils/graphql/legacy_user_fields_link.dart';
import '../utils/logger/logger_link.dart';
import '../utils/mixin/shared_preferences_client_mixin.dart';
import '../utils/network/graphql_errors.dart';
import '../utils/network/timeout_http_client.dart';

part 'global_providers.g.dart';

/// Replay only reads after handover: a mutation may already have reached the server.
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

final _legacyUserFieldsDetectionProvider =
    Provider.autoDispose<LegacyUserFieldsDetection>((ref) {
      ref.watch(serverUrlProvider);
      ref.watch(serverPortProvider);
      ref.watch(serverPortToggleProvider);
      return LegacyUserFieldsDetection();
    });

@Riverpod(keepAlive: true)
GraphQLClient graphQlClient(Ref ref) {
  final isCurrentSession = watchAuthSession(ref);
  final authType = ref.watch(authTypeKeyProvider) ?? DBKeys.authType.initial;
  // Watch credentials to drop cached results on change; read their value per request.
  ref.watch(credentialsProvider);

  final timeoutMs =
      ref.watch(serverRequestTimeoutProvider) ??
      DBKeys.serverRequestTimeout.initial as int;
  final autoRetry = ref.watch(autoRefreshOnTimeoutProvider).ifNull();
  final retryDelayMs =
      ref.watch(autoRefreshRetryDelayProvider) ??
      DBKeys.autoRefreshRetryDelay.initial as int;

  // Client aborts leave server fetches running, so each retry gets the full timeout.
  final effectiveTimeoutMs = timeoutMs;
  final retryCount = autoRetry ? TimeoutConstants.autoRefreshMaxRetries : 0;

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
      retryHeaders: authType != AuthType.uiLogin
          ? null
          : (headers) async {
              const key = 'authorization';
              final carriesToken = headers.entries.any(
                (e) =>
                    e.key.toLowerCase() == key && e.value.startsWith('Bearer '),
              );
              if (!carriesToken) return headers;
              final token = await ref
                  .read(authCoordinatorProvider.notifier)
                  .usableUiAccessToken(
                    gqlClient: () =>
                        ref.read(unauthenticatedGraphQlClientProvider),
                    trigger: 'request-retry',
                  );
              return {
                for (final e in headers.entries)
                  if (e.key.toLowerCase() != key) e.key: e.value,
                if (token != null) 'Authorization': 'Bearer $token',
              };
            },
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

  // TimeoutHttpClient owns retries; do not add RetryLink retries.

  // Await credentials per request because secure storage resolves asynchronously.
  if (authType == AuthType.basic) {
    final AuthLink authLink = AuthLink(
      getToken: () async {
        final stored = await ref.read(credentialsProvider.future);
        return stored.isNotBlank ? stored : null;
      },
    );
    link = authLink.concat(link);
  }

  if (authType == AuthType.simpleLogin || authType == AuthType.uiLogin) {
    final suwayomiAuthLink = SuwayomiAuthLink(
      isCurrentSession: isCurrentSession,
      authType: () => authType,
      getHeaders: () async {
        final Map<String, String>? base;
        if (authType == AuthType.uiLogin) {
          final token = await ref
              .read(authCoordinatorProvider.notifier)
              .usableUiAccessToken(
                gqlClient: () => ref.read(unauthenticatedGraphQlClientProvider),
                trigger: 'request-ahead',
              );
          base = token == null ? null : {'Authorization': 'Bearer $token'};
        } else {
          // Await settings even if a request precedes the eager preload.
          final snapshot = await ref.read(authCredentialsStoreProvider.future);
          base = snapshot.simpleLoginCookieHeader;
        }
        final custom = ref.read(customHttpHeadersProvider).value ?? const {};
        if (base == null) {
          return custom.isEmpty ? null : Map<String, String>.from(custom);
        }
        return applyCustomHeaders(Map<String, String>.from(base), custom);
      },
      refreshAccessToken: () async {
        // simple_login short-circuits before this ui_login-only refresh callback.
        if (authType != AuthType.uiLogin) {
          return const RefreshAuthFailure();
        }
        // Refresh through an unauthenticated client to avoid recursive auth; the coordinator deduplicates.
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
            .refreshUiAccessToken(gqlClient: rawClient, trigger: 'auth-link');
      },
      onNeedsReauth: () {
        if (ref.read(hasStoredCredentialsProvider)) {
          ref.read(needsReauthProvider.notifier).set(true);
        }
      },
    );
    link = suwayomiAuthLink.concat(link);
  }

  // Defer reachability updates because responses may arrive during provider builds.
  final reachabilityLink = Link.function((request, [forward]) {
    return forward!(request)
        .map((response) {
          if (response.errors?.any(
                (e) => isAuthenticationRequired(
                  OperationException(graphqlErrors: [e]),
                ),
              ) ==
              true) {
            Future(() {
              if (ref.mounted && isCurrentSession()) {
                ref
                    .read(authModeReconcilerProvider)
                    .reconcile(authFailure: true);
              }
            });
          }
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
          if (isAuthenticationRequired(error) || isBasicGatedNotFound(error)) {
            Future(() {
              if (ref.mounted && isCurrentSession()) {
                ref
                    .read(authModeReconcilerProvider)
                    .reconcile(authFailure: true);
              }
            });
          }
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

  final loggerLink = LoggerLink().concat(
    LegacyUserFieldsLink(
      detection: ref.watch(_legacyUserFieldsDetectionProvider),
    ),
  );
  return GraphQLClient(
    link: _sessionLink(isCurrentSession).concat(loggerLink).concat(link),
    defaultPolicies: DefaultPolicies(
      query: Policies(fetch: FetchPolicy.noCache),
    ),
    // Cover the HTTP retry window plus 2s so GraphQL's own timeout cannot preempt it.
    queryRequestTimeout: Duration(
      milliseconds:
          timeoutMs * (retryCount + 1) + retryDelayMs * retryCount + 2000,
    ),
    // noCache makes a persisted store write-only; keep it in memory.
    cache: GraphQLCache(store: InMemoryStore()),
  );
}

/// The server binds socket identity at connect; refresh first and omit expired tokens on failure.
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
  final live = socketTokenIsLive(token);
  _wsAuthLog(
    'connect-init ${describeSocketToken(token)}'
    '${live || token == null || token.isEmpty ? '' : ' withheld=expired'}',
  );
  return live
      ? <String, dynamic>{'Authorization': token!}
      : <String, dynamic>{};
}

/// Log token expiry, never the token itself.
@visibleForTesting
String describeSocketToken(String? token, {DateTime? now}) {
  if (token == null || token.isEmpty) return 'token=none';
  final exp = decodeJwtExp(token);
  if (exp == null) return 'exp=unknown';
  return 'expIn=${exp.difference(now ?? DateTime.now().toUtc()).inSeconds}s';
}

/// Tokens without a readable expiry count as live.
@visibleForTesting
bool socketTokenIsLive(String? token, {DateTime? now}) {
  if (token == null || token.isEmpty) return false;
  final exp = decodeJwtExp(token);
  return exp == null || exp.isAfter(now ?? DateTime.now().toUtc());
}

void _wsAuthLog(String event) =>
    recordDiagnostic('[${DateTime.now().toIso8601String()}] ws-auth: $event\n');

@Riverpod(keepAlive: true)
GraphQLClient graphQlSubscriptionClient(Ref ref) {
  final isCurrentSession = watchAuthSession(ref);
  final authType = ref.watch(authTypeKeyProvider) ?? DBKeys.authType.initial;
  final credentials = ref.watch(credentialsProvider).value;
  // Watch only the handshake cookie; per-connect tokens must not rebuild live subscriptions.
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

  // Socket auth: ui_login uses connection_init {Authorization: <bare token>}; basic/simple use upgrade headers.
  dynamic initialPayload;
  Map<String, String>? handshakeHeaders;
  var boundAsVisitor = false;
  if (authType == AuthType.uiLogin) {
    // Async settings can dispose this socket during refresh; check ref.mounted before accessing ref.
    initialPayload = () => uiLoginSocketPayload(
      isCurrentSession: isCurrentSession,
      refreshIfDue: () async {
        if (!ref.mounted) {
          _wsAuthLog('connect-refresh skipped=provider-disposed');
          return;
        }
        // Socket connects are not awaited by handover, so refresh may safely wait outside its zone.
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
            RefreshTransientFailure(:final error) => 'transient cause=${error.runtimeType}: '
                '${error.toString().split('\n').first}',
          }}',
        );
      },
      readToken: () async {
        if (!ref.mounted) {
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
    // A visitor-bound socket needs reconnection when a live token arrives; other refreshes need none.
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
  // Close replaced sockets to avoid leaking connections.
  ref.onDispose(() => unawaited(wsLink.dispose().catchError((_) {})));

  final loggerLink = LoggerLink().concat(
    LegacyUserFieldsLink(
      detection: ref.watch(_legacyUserFieldsDetectionProvider),
      // Stable servers reject introspection queries over the socket.
      probe: (request) => ref.read(graphQlClientProvider).link.request(request),
    ),
  );
  final timeoutMs =
      ref.watch(serverRequestTimeoutProvider) ??
      DBKeys.serverRequestTimeout.initial as int;
  return GraphQLClient(
    link: _sessionLink(isCurrentSession).concat(loggerLink).concat(wsLink),
    defaultPolicies: DefaultPolicies(
      query: Policies(fetch: FetchPolicy.noCache),
    ),
    // Cover the same retry window as the HTTP query client.
    queryRequestTimeout: Duration(milliseconds: timeoutMs + 2000),
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
