# Data Layer

## Purpose

All manga/chapter/library data is fetched via the Suwayomi GraphQL API (`/api/graphql`); images come from a REST surface. Settings persist locally via SharedPreferences; Hive backs the GraphQL cache store.

## Key files

| Path | Responsibility |
|---|---|
| `lib/src/global_providers/global_providers.dart` | Creates/provides the HTTP + WebSocket `GraphQLClient`s, `SharedPreferences`, `HiveStore`, rate-limit queue, top-level prefs |
| `lib/src/graphql/schema.graphql` / `fragments.graphql` | Full schema; shared `PageInfoDto` fragment |
| `lib/src/graphql/__generated__/*.graphql.dart` | Codegen output (inputs, enums, scalars, fragments) |
| `lib/src/constants/endpoints.dart` | `Endpoints.baseApi(...)` — the single URL builder (HTTP/GraphQL/WebSocket, port toggle) |
| `lib/src/constants/db_keys.dart` | `DBKeys` — every SharedPreferences key + default |
| `lib/src/utils/mixin/shared_preferences_client_mixin.dart` | `SharedPreferenceClientMixin<T>` / `SharedPreferenceEnumClientMixin<T>` |
| `lib/src/widgets/server_image.dart` | `ServerImage` — `CachedNetworkImage` with per-auth-type header/token injection |
| `lib/src/utils/extensions/cache_manager_extensions.dart` | Same auth/URL logic for imperative `CacheManager.getSingleFile` |
| `lib/src/features/<f>/data/<name>_repository.dart` (+ `graphql/*.graphql`) | Per-feature repositories + operations |

## The two GraphQL clients

**`graphQlClientProvider`** (HTTP queries/mutations):
- `HttpLink` to `Endpoints.baseApi(..., isGraphQl: true)`, wrapped in `TimeoutHttpClient` (configurable timeout + retry).
- Auth links prepended per `authTypeKeyProvider`: `basic` → `AuthLink`; `simpleLogin`/`uiLogin` → `SuwayomiAuthLink` (see [auth.md](auth.md)).
- Cache: `GraphQLCache(store: hiveStoreProvider)`, default `FetchPolicy.noCache` — **every query hits the network**; Hive is effectively write-only.

**`graphQlSubscriptionClientProvider`** (WebSocket subscriptions):
- `WebSocketLink`, `subProtocol: graphqlTransportWs`.
- **Auth is on the socket, not a Link**: `ui_login` → `initialPayload` async fn returning `{Authorization: <bare token>}` (no "Bearer "); `simple_login`/`basic` → `handshakeHeaders`.

**`graphQlClientNotifierProvider`** — `ValueNotifier<GraphQLClient>` for the `GraphQLProvider` widget.

## Repository pattern

```
features/<f>/data/<name>_repository.dart      # class taking GraphQLClient + @riverpod factory
features/<f>/data/graphql/query.graphql       # operations
features/<f>/data/graphql/__generated__/...    # graphql_codegen output
features/<f>/domain/<type>/graphql/fragment.graphql  # fragments near their domain type
```

- Repository methods call codegen extension methods: `client.query$AllCategories()`, `client.mutate$CreateCategory(Options$Mutation$CreateCategory(variables: ...))` — not raw `client.query(QueryOptions(...))`.
- The `@riverpod` factory is a one-liner: `CategoryRepository(ref.watch(graphQlClientProvider))`.
- After changing `.graphql` files or `@riverpod`: `dart run build_runner build --delete-conflicting-outputs`.

## Riverpod conventions

- `@riverpod` on a function → `AutoDisposeProvider<T>` (repositories).
- `@riverpod` on a class extending `_$X` → `AutoDisposeNotifierProvider<T?>`.
- **Persisted prefs** follow the mixin pattern: class mixes `SharedPreference[Enum]ClientMixin`, `build()` calls `initialize(DBKeys.key)` (watches `sharedPreferencesProvider`, `ref.listenSelf` auto-persists), callers use `.update(value)`.
- `sharedPreferencesProvider` and `hiveStoreProvider` are `throw UnimplementedError()` sentinels — overridden in `ProviderScope` at startup.

## Image / CacheManager auth

- `basic` → `Authorization` header.
- `simple_login` → `Cookie` header (watched reactively via `.select`).
- `ui_login` → token as `?token=<urlencoded>` query param (headers unreliable for `cached_network_image`); **`cacheKey` is always the bare `baseApi` URL (no token)** so cache survives token rotation; token read via `ref.read` (non-reactive) to avoid rebuild storms in webtoon scroll.

## Gotchas

- **WebSocket auth via a `Link` is silently ineffective** — must use `initialPayload`/`SocketClientConfig.headers`. (Cost a debug session historically.)
- **`ui_login` WS sends a bare token, not `Bearer <token>`** (server `onInit` doesn't strip the prefix). HTTP uses `Bearer`.
- **`cacheKey` must be the un-tokened URL** — otherwise every token rotation busts the whole image cache.
- **Subscription 401 mid-stream is not handled** — `SuwayomiAuthLink` only inspects the first event. Acceptable because Suwayomi subscriptions are short-lived.
- **Token refresh uses a raw, un-authed client** to avoid infinite recursion on 401.
- **Default `FetchPolicy.noCache`** — don't expect GraphQL cache reads.
