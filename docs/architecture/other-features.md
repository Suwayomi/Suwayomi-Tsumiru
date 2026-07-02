# Other Features

Smaller features: about, history, migration, offline, quick_open.

## about

App/server version info + update checks.

- `data/about_repository.dart` — **two update paths**: `checkUpdate()` hits the **GitHub Releases REST API** directly; `checkServerUpdate()` uses the server's GraphQL `checkForServerUpdates`. Both use `pub_semver`.
- `controllers/about_controller.dart` — `aboutProvider` (GraphQL `GetAbout`); `packageInfoProvider` is `throw UnimplementedError()` (overridden in `main.dart`).
- URLs (all in `lib/src/constants/urls.dart`): `sorayomiGithubUrl` = `github.com/tsumiru-app/tsumiru`, `sorayomiLatestReleaseUrl`/`...ApiUrl` (releases + GitHub API), `sorayomiWhatsNew` = GitHub releases page, `tachideskHelp` = `tsumiru.app/docs/...`.
- **Gotcha:** the update check strips the leading `v` from `tag_name` (`Version.parse(tag.substring(1))`) — a tag format change throws. (This was the crash fixed in `33dbd31`.)

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
