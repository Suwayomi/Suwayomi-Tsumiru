# Other Features

Smaller features: about, history, migration, offline, quick_open.

## about

App/server version info + update checks.

- `data/about_repository.dart` — **two update paths**: `checkUpdate()` hits the **GitHub Releases REST API** directly in ordinary native/standalone builds; `checkServerUpdate()` uses the server's GraphQL `checkForServerUpdates`. Both use `pub_semver`.
- `controllers/about_controller.dart` — `aboutProvider` (GraphQL `GetAbout`); `packageInfoProvider` is `throw UnimplementedError()` (overridden in `main.dart`).
- URLs (all in `lib/src/constants/urls.dart`): `githubUrl` = `github.com/Suwayomi/Suwayomi-Tsumiru`, `latestReleaseUrl`/`...ApiUrl` (releases + GitHub API), `whatsNew` = GitHub releases page, `tachideskHelp` = `tsumiru.app/docs/...`.
- Release checks accept version tags with or without a leading `v`, then compare versions with `pub_semver`.
- About includes a localized Privacy policy row linking to `https://tsumiru.app/privacy/` in every distribution.
- With `--dart-define=TSUMIRU_GOOGLE_PLAY=true`, `isGooglePlayBuild` disables app-version HTTP requests in both `AboutRepository` and `NotificationBackgroundClient`. The shell skips app-update startup work, and the shared dialog suppresses app prompts. Server dialogs use an explicit `isServerUpdate` flag, including when their release URL is absent.
- Play builds hide the client update row, app-update notification toggle and its settings-search entry. The settings provider ignores stored app-update preferences without overwriting them. `NotificationWorkerConfig.appUpdatesEnabled` is effectively false even for directly constructed or stale JSON configurations, so app-only checks cannot schedule a worker. Server, extension and chapter checks retain their normal behavior. What's New and project/help links remain available.
- macOS in-app updates go through Sparkle's standard UI instead of GitHub when configured: `data/macos_app_updater.dart` (import-safe off macOS) drives the native `TsumiruSparkleUpdater` over the `tsumiru/sparkle_updater` channel (`initialize`/`checkForUpdates`). The About screen prefers the native check and falls back to GitHub only when the native controller is missing or broken (a busy updater still counts as handled, so no second prompt appears). Startup skips the GitHub app check when the native updater is available but server alerts still run. Build and activation live in [repo-build-release.md](repo-build-release.md#macos-sparkle-updates).
- Server-hosted web builds continue to use server-managed web updates. See [repo-build-release.md](repo-build-release.md#google-play-distribution-mode) for build and test commands.

## history

Per-manga reading history grouped by date, with search + per-item removal.

- `data/history_repository.dart` — GraphQL with `ChapterFilterInput` (`lastReadAt`/`isRead`/`lastPageRead`); **dedup is client-side** (over-fetches `pageSize*10`, keeps most-recent chapter per manga, re-paginates). `clearAllHistory()` is `throw UnimplementedError`.
- `presentation/history_controller.dart` — `ReadingHistory` notifier; `removeFromHistory()` patches `isRead=false, lastPageRead=0` (no true delete; `lastReadAt` can't be cleared via the API).
- `HistoryGroup` (freezed) groups by date key with localized headers.
- **Gotchas:** the `pageSize*10` over-fetch can be slow at scale; removed items may reappear until server restart; manga-title search is client-side only.

## migration

Migrate a manga from one source to another (status/categories/progress/bookmarks, optional source delete). Five-screen flow.

- `data/migration_repository.dart` — sequential GraphQL; chapter matching by number (±0.01) → exact name → partial name; chapters updated one-by-one. `cancelMigration()` is `throw UnimplementedError`.
- `controller/migration_controller.dart` — `MigrationExecution` notifier with **artificial progress delays**; global search via `rateLimitQueueProvider`.
- **Gotchas:** `migrateDownloads` and `migrateTracking` flags exist in the UI but are **not implemented**; cancel is unimplemented (controller fakes `cancelled`); progress percentages are cosmetic (real work happens at the 75%→100% step).

## offline

Offline reading is a full subsystem with its own doc — see [offline.md](offline.md).

## quick_open

Command-palette overlay for fast navigation (library/manga/chapters/sources via typed prefixes).

- `controller/quick_search_controller.dart` — `processesQuickSearchProvider` routes by prefix/context: `?` help, `@source` / `@source/query` sources, `#cat` / `#cat/manga` / `#cat/manga:chapter` library drill-down, context-aware default (chapter search on a manga route, else manga search).
- `domain/quick_search_result.dart` — `QuickSearchResult` freezed union (helpText/source/category/manga/chapter/globalSearch/...).
- `widgets/search_stack_screen.dart` stacks the overlay on the shell.
- **Gotcha:** `processesQuickSearchProvider` takes a `BuildContext` (for `context.location` route awareness) — unusual for Riverpod; it must be called from a widget subtree and falls back to manga search if route parsing fails.
