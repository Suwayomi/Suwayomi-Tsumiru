# App Shell & Navigation

## Purpose

App bootstrap, the `go_router` typed route tree, and the stateful navigation shell (NavigationRail on tablet/desktop, bottom NavigationBar on phone).

## Key files

| Path | Responsibility |
|---|---|
| `lib/main.dart` | Bootstrap: Hive init, auth migration, auth preload, `ProviderContainer` setup, `runApp` |
| `lib/src/sorayomi.dart` | Root widget `Sorayomi`; wires `GraphQLProvider`, `MaterialApp.router`, theming, locale, `ReauthBannerHost` |
| `lib/src/routes/router_config.dart` | `@riverpod routerConfig` `GoRouter`; typed `ShellRoute`/`GoRoute` defs; `Routes` constants; navigator keys |
| `lib/src/routes/router_config.g.dart` | Generated `$appRoutes` (build_runner) |
| `lib/src/routes/sub_routes/*.dart` | `part` files, one per nav section |
| `lib/src/widgets/shell/navigation_shell_screen.dart` | `NavigationShellScreen` — dispatches to big/small nav bar; runs update check on first mount |
| `lib/src/widgets/shell/big_screen_navigation_bar.dart` | `BigScreenNavigationBar` — `NavigationRail` (extended on desktop, logo in leading) |
| `lib/src/widgets/shell/small_screen_navigation_bar.dart` | `SmallScreenNavigationBar` — M3 bottom `NavigationBar` |
| `lib/src/constants/navigation_bar_data.dart` | `NavigationBarData` — `phoneNavList`/`tabletNavList`, `getNavList(context)` |

## Bootstrap sequence (`main()`)

1. `WidgetsFlutterBinding.ensureInitialized()`, `PackageInfo.fromPlatform()`, `SharedPreferences.getInstance()`, `initHiveForFlutter()`.
2. `GoRouter.optionURLReflectsImperativeAPIs = true`.
3. `ProviderContainer` with three pre-seeded overrides: `packageInfoProvider`, `sharedPreferencesProvider`, `hiveStoreProvider`.
4. `migrateBasicAuthCredentials` — one-shot legacy basic-auth → secure storage migration (non-fatal).
5. `Future.wait([authCredentialsStoreProvider.future, credentialsProvider.future])` — both auth providers loaded **before first frame** (prevents tokenless image requests caching as 401s).
6. `container.read(authCoordinatorProvider.notifier)` — eagerly construct so the proactive-refresh listener is live before any image request.
7. `runApp(UncontrolledProviderScope(container, child: Sorayomi()))`.

Initial location: `/library/0`.

`Sorayomi.build()` wraps: `GraphQLProvider` → `MaterialApp.router` → `FToastBuilder` → `ReauthBannerHost`.

## Routing

`go_router` with typed routes (`@TypedShellRoute` / `@TypedGoRoute` / `@TypedStatefulShellRoute`) generated into `router_config.g.dart`. The `GoRouter` itself is a `@riverpod` provider (`routerConfigProvider`).

Route tree (outer → inner):

```
QuickSearchRoute (ShellRouteData — wraps everything in SearchStackScreen)
  NavigationShellRoute (StatefulShellRouteData — NavigationShellScreen)
    LibraryBranch    → /library/:categoryId
    UpdatesBranch    → /updates
    HistoryBranch    → /history
    BrowserBranch    → BrowseShellRoute (nested StatefulShellRoute: Sources / Extensions)
    DownloadsBranch  → /downloads
    MoreBranch       → /more → settings, about, ...
  MangaRoute         → /manga/:mangaId            (outside the shell)
    ReaderRoute      → /manga/:mangaId/chapter/:chapterId
  GlobalSearchRoute, UpdateStatusRoute, Migration*Route
```

Navigator keys: `rootNavigatorKey`, `_quickOpenNavigatorKey` (also `$parentNavigatorKey` for `ReaderRoute`/`GlobalSearchRoute` → they present full-screen above the shell), `_shellNavigatorKey`, `_browseNavigatorKey`.

Navigation is always typed: `const FooRoute(...).go(context)` / `.push(context)` — no string-based navigation.

## Screen-size split

- **Phone** (< 600): `SmallScreenNavigationBar` (M3 bottom bar), 5 items (History omitted — lives under More).
- **Tablet** (≥ 600, `context.isTablet`): `BigScreenNavigationBar` (`NavigationRail`), 6 items incl. History.
- **Desktop** (≥ 1200, `context.isDesktop`): rail is **extended** (256px) with logo + title in `leading`.

## Gotchas

- **History index offset on phone.** The stateful shell always has 6 branches (0–5); phone shows 5 (History hidden). `NavigationShellScreen` has `getAdjustedIndex`/`getReverseAdjustedIndex` that ±1 for indices ≥ 2 on phone. Changing the nav item count must update these or the wrong branch is selected.
- **Reader presents above the shell** via `_quickOpenNavigatorKey` as `$parentNavigatorKey` — nav bars are fully hidden while reading.
- **`MangaRoute` is outside the stateful shell** (inside `QuickSearchRoute`) — manga detail renders without a nav bar.
- **`NavigationBarData.navList`** (static field) is a stale legacy alias for `phoneNavList`; always use `getNavList(context)`.
- **Browse is a tab-within-a-tab** — a nested `StatefulShellRoute` (Sources / Extensions) with its own navigator.
- **`isTablet` uses `width`, not shortestSide** despite a misleading comment — a landscape phone ≥ 600px wide gets the rail layout.
