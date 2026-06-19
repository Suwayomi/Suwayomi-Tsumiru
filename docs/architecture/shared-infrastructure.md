# Shared Infrastructure

`constants/`, `utils/`, shared `widgets/`, `abstracts/` — the persistence registry, app-wide enums/constants, the context-extension toolkit, auth-aware image fetching, and reusable widgets every feature draws on.

## DBKeys — the prefs registry

`lib/src/constants/db_keys.dart` — a single enum that is the authoritative list of every SharedPreferences key, each case carrying its `initial` value as a constructor arg. The key string on disk = the enum case `.name`. Companion `DBStoreName` enum (`settings`) names the Hive store.

**The two mixins** (`lib/src/utils/mixin/shared_preferences_client_mixin.dart`):

- `SharedPreferenceClientMixin<T>` — non-enum types (bool/double/int/String/List\<String\>, or custom via `toJson`/`fromJson`). `initialize(DBKeys.key)` watches `sharedPreferencesProvider`, sets `_key = key.name`, reads `key.initial`, registers `ref.listenSelf` to auto-persist. `_set` dispatches by type; `null` → `remove`. Public: `update(T?)`, `updateWithPreviousState(...)`.
- `SharedPreferenceEnumClientMixin<T extends Enum>` — stores the enum **index** via `setInt`; `initialize(DBKeys.key, enumList: SomeEnum.values)`.

## Constants

- **`enum.dart`:** `AuthType` (none/basic/simpleLogin/uiLogin), `ReaderMode` (8; default webtoon), `ReaderNavigationLayout` (default disabled), `MangaSort` (7; default lastRead), `ChapterSort` (source/uploadDate/fetchedDate), `DisplayMode` (grid/list/descriptiveList), `MangaStatus`, `IncludeOrExclude` (tri-state). Most carry `toLocale(BuildContext)`.
- **`urls.dart`:** external URLs, rebranded to `tsumiru-app` (`sorayomiGithubUrl`, `...LatestReleaseUrl`, `...ApiUrl`, `tachideskHelp`, `sorayomiWhatsNew`, `flareSolverr`).
- **`endpoints.dart`:** `Endpoints.baseApi(...)` — the central URL builder (`baseUrl`, `port`, `addPort`, `isGraphQl`, `isWebsocket`); plus per-area URL classes.
- **`app_constants.dart`:** `kDuration` (500ms), `kInstantDuration`, `kLongDuration`, `kCurve`, magnifier constants, `kDebounceDuration` (500ms), `kPositionPlaceholder` (-1).
- **`app_sizes.dart`:** `KEdgeInsets` / `KBorderRadius` / `KRadius` tokens; `mangaCoverGridDelegate(double?)`.
- **`gen/assets.gen.dart`:** FlutterGen output. `Assets.icons.darkIcon` / `lightIcon` are the Tsumiru icons; the `launcher` sub-namespace still uses old `sorayomi*` file names (matches on-disk asset names).

## Utils

- **Context extensions** (`utils/extensions/custom_extensions/context_extensions.dart`): `context.l10n`, `isDesktop` (≥1200), `isTablet` (≥600), `showNavbar` (>800), `theme`/`textTheme`/`colorScheme`/`isDarkMode`, `responsiveValue<T>(...)`, `pushBottomSheet`, `showFullScreenDialog`, `location` (current GoRouter path).
- **`cache_manager_extensions.dart`:** `CacheManager.getServerFile(ref, url)` — mirrors `ServerImage` auth (ui_login token as `?token=`, cacheKey = untokened `baseApi`).
- **`async_value_extensions.dart`:** `showUiWhenData(context, builder, ...)` (shimmer / `Emoticons` error / builder), `valueOrToast`, `copyWithData`.
- **String/int/bool extensions:** `isBlank`/`isNotBlank`, `query(...)`, `parseTimestamp`; `liesBetween`, `getValueOnNullOrNegative`, `compact`; `bool?.ifNull([alt=false])` (used everywhere instead of `?? false`).
- **`app_utils.dart`:** `wrapOn(wrapper, child)`, `guard<T>(future, toast)`.
- **`toast/toast.dart`:** `Toast` (FToast wrapper); `toast` provider returns `Toast?` (null when no context) — callers null-check.

## Shared widgets

- **`ServerImage`** (`widgets/server_image.dart`): auth-aware `CachedNetworkImage`. Dispatches by `authTypeKeyProvider`; `simple_login` cookie watched reactively (`.select`), `ui_login` token via `ref.read` (non-reactive, to avoid webtoon rebuild storms), `cacheKey = baseApi` (untokened). Error widget evicts cache + speculatively refreshes the token + remounts. `ServerImageWithCpi` adds a progress ring.
- **`MangaCoverGridTile` / `MangaBadgesRow` / `MangaBadge`** (`widgets/manga_cover/`): cover tiles with `showTitle`/`showBadges`/`showCountBadges`; badges read `downloadedBadgeProvider` / `unreadBadgeProvider`. `languageBadge` is commented out.
- **Async buttons** (`widgets/async_buttons/`): six variants, all `useState(false)` loading → disable + spinner.
- **`Emoticons`** (error state), **`CenterSorayomiShimmerIndicator`** (loading), **popup widgets** (Radio/MultiSelect/Slider/TextField popups), **`SettingsPropTile`** (generic settings row).
- **Shell widgets** (`widgets/shell/`): see [app-shell-navigation.md](app-shell-navigation.md).

## Gotchas

- **Enums are stored by index** (`SharedPreferenceEnumClientMixin`) — reordering cases silently corrupts stored prefs (`ReaderMode`, `ReaderNavigationLayout`, `MangaSort`, `ChapterSort`, `DisplayMode`).
- **`DBKeys` key = enum case `.name`** — renaming is a breaking migration.
- **`ServerImage` uses `ref.read` for the ui token** (not `watch`) — deliberate, to avoid scroll-yanking rebuild storms on the ~4-min token rotation.
- **`cacheKey = baseApi` (untokened), fetch URL = tokened** — keep this split for any new auth mode or token rotation busts the cache.
- **`languageBadge` is fully commented out** (the `DBKeys.languageBadge` key exists but no live provider reads it).
- **Launcher assets still use `sorayomi*` names** in `assets.gen.dart` (on-disk file names not yet renamed).
- **`AuthType` has four values** — any `switch` on it must handle all four.
- **`isDesktop` (≥1200) ≠ `showNavbar` (>800)** — distinct thresholds.
