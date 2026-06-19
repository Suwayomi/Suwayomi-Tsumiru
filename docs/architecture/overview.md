# Overview

## Tech stack

- **Flutter 3.32.4 / Dart 3.8.1** (pinned).
- **Riverpod** (`hooks_riverpod`) + `riverpod_generator` (`@riverpod`) for state/DI.
- **flutter_hooks** for local widget state.
- **graphql_flutter** + **graphql_codegen** for the Suwayomi GraphQL API.
- **freezed** + **json_serializable** for data classes.
- **go_router** + **go_router_builder** for typed routing.
- **flex_color_scheme** for theming.
- **scrollable_positioned_list** (a pinned fork) for the multi-image readers.
- **cached_network_image** + **flutter_cache_manager** for image fetches.
- **flutter_secure_storage** for credentials; **shared_preferences** for settings; **Hive** for the GraphQL cache store.

After adding `@riverpod` annotations or `.graphql` files: `dart run build_runner build --delete-conflicting-outputs`.

## Layered structure

```
lib/
  main.dart                 # bootstrap: Hive, prefs, auth preload, runApp
  src/
    sorayomi.dart           # root widget: GraphQLProvider + MaterialApp.router + theming
    routes/                 # go_router typed route tree (+ sub_routes/ part files)
    global_providers/       # GraphQL clients, SharedPreferences, HiveStore, auth-type
    graphql/                # shared schema + fragments + codegen output
    constants/              # DBKeys (prefs registry), enums, urls, endpoints, sizes, gen assets
    utils/                  # context extensions, the SharedPreference mixins, AsyncValue helpers
    widgets/                # shared widgets (ServerImage, manga covers, async buttons, shell nav)
    l10n/                   # ARB files + generated localizations
    features/<area>/        # per-feature: data/ (repository + .graphql), domain/ (typedefs), presentation/ (screens + controllers)
```

Each feature follows the same internal shape: `data/` (a repository class + a `@riverpod` factory + `.graphql` operations), `domain/` (mostly `typedef`s over GraphQL codegen fragments), `presentation/` (screens + `controller/` providers + `widgets/`).

## Conventions reused everywhere

These appear across every feature — learn them once:

- **Persisted setting:** add a case to `DBKeys` (with its default), declare a `@riverpod` notifier that mixes in `SharedPreferenceClientMixin<T>` (or `SharedPreferenceEnumClientMixin<T>` for enums), call `initialize(DBKeys.yourKey)` in `build()`. Read/persist is automatic via `ref.listenSelf`. See [shared-infrastructure.md](shared-infrastructure.md).
- **Repository:** a plain class taking a `GraphQLClient`, calling codegen extension methods (`client.query$Foo()`, `client.mutate$Bar(...)`), plus a `@riverpod` factory injecting `graphQlClientProvider`. See [data-layer.md](data-layer.md).
- **Domain types are `typedef`s** over generated fragments (`typedef MangaDto = Fragment$MangaDto`), not bespoke classes (except a few `freezed` ones).
- **Async UI:** `asyncValue.showUiWhenData(context, builder)` renders a shimmer while loading and an `Emoticons` error widget on error — skip custom loading/error handling.
- **Async mutations:** `AppUtils.guard(future, toast)` runs a future, surfaces errors as a toast, returns `T?`.
- **Strings:** all user-facing text goes through `context.l10n.someKey` (ARB/l10n). No hardcoded strings.
- **Sizes:** use `KEdgeInsets.X.size` / `KBorderRadius.X.radius` tokens, never hardcoded padding/radii.
- **Responsive:** `context.isDesktop` (width ≥ 1200), `context.isTablet` (≥ 600), `context.showNavbar` (> 800) — distinct thresholds, don't conflate.

## The big cross-cutting gotchas

- **`SharedPreferenceEnumClientMixin` stores enums by index**, not name — reordering enum cases silently corrupts stored prefs (`ReaderMode`, `MangaSort`, `DisplayMode`, etc.).
- **`DBKeys` key string = the enum case `.name`** — renaming a case is a breaking migration.
- **Two GraphQL clients** (HTTP + WebSocket). WebSocket auth must be on the socket (`initialPayload`/`handshakeHeaders`), never a `Link`. See [auth.md](auth.md) / [data-layer.md](data-layer.md).
- **Several "fetch" operations are mutations** (`fetchChapters`, `FetchExtensionList`) — calling them triggers a server-side source refresh, not just a DB read.
