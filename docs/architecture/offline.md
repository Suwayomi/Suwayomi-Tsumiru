# Offline reading

Save chapters to the device and read them with **no server connection**, with automatic fallback to local copies when the server is unreachable. Native-only (Android / desktop); the whole subsystem is inert on web. Lives under `lib/src/features/offline/`.

## On-device catalog

`data/offline_database.dart` — a Drift / SQLite database (`OfflineDatabase`, schemaVersion 7) at `<appSupport>/offline/catalog.sqlite`. Tables:

- `OfflineMangas` — `id` (server manga id) PK; `title`, `thumbnailUrl`, `thumbnailRelPath`, `keepRule` (`OfflineKeepRule`, default `off`), `keepUnreadCount` (default 3).
- `OfflineChapters` — `id` (server chapter id) PK, indexed by `mangaId`; `deviceState` (`OfflineDeviceState`, default `none`), `pageCount`, `bytes`, `pinned`, `downloadedAt`, `serverIsDownloaded`, read state, and three independent "not yet pushed" flags — `progressDirty` (position), `readStateDirty` (isRead), `bookmarkDirty` (isBookmarked). Each field syncs under its own flag so a position-only write can never push a stale isRead (the ch-99 un-read loop) and a read/bookmark change set elsewhere still lands locally while another is pending.
- `OfflineCategories`, `OfflineMangaCategories`, and `OfflinePages` (`(chapterId, pageIndex)` → `relativePath`).

Design notes: there is **no foreign key** from chapters to mangas — a chapter whose server manga is gone becomes `deviceState = orphaned` instead of cascade-deleting. The metadata upserts (`upsertMangaMetadata` / `upsertChapterMetadata`) deliberately exclude device-managed columns (`deviceState`, `bytes`, `thumbnailRelPath`) from `ON CONFLICT UPDATE`, so a metadata sync can never clobber download state.

`data/offline_repository.dart` — `OfflineRepository`, the single interface over Drift (`localChapterPages`, `watchChapterState`, `keepRuleFor`, …). `data/offline_paths.dart` — `OfflinePaths`, pure path arithmetic (`<mangaId>/<chapterId>/<NNN>.<ext>`, forward-slash relative paths). `data/offline_page_store*.dart` — `OfflinePageStore` (abstract) + `IoOfflinePageStore` (writes page bytes to disk).

## Download pipeline

Four layers, all driven through one entry point — **`downloadStarterProvider`** (never call the lower layers directly):

1. `chapter_download_engine.dart` — `ChapterDownloadEngine` downloads one chapter's pages with up to N concurrent workers (N = `OfflineDownloadConcurrency`, default 2), each page retried 3× with backoff. `PageAuthException` → one auth refresh + retry; `PageOfflineException` → stop and leave the run resumable.
2. `offline_download_coordinator.dart` — `OfflineDownloadCoordinator` queues and runs **one chapter at a time** (Komikku model) via the engine; `pumpDownloads()` drains the queue. Process-wide single-flight via a `static _pumping` flag. The coordinator and engine providers are **keep-alive**: nothing watches them (all consumers are one-shot reads), and an auto-dispose Ref dies at the first async gap — under Riverpod 3 its call-time reads then throw `UnmountedRefException`, which silently killed launch resume and the desktop pump.
3. `offline_download_providers.dart` — the wiring + the public surface: `saveChapterToDevice`, `deleteChapterFromDevice`, `reconcileManga`, `recordReadingProgress`, `recordReadState` (offline-aware write-through for mark-read/unread), `pushPendingProgress`, and the state streams (`offlineChapterStateProvider`, `mangaOfflineProgressProvider`, `mangaKeepRuleProvider`, …).
4. `data/background/` — **Android only**: `BackgroundDownloadController` owns a `FlutterForegroundTask` foreground service (its own isolate, `download_task_handler.dart`) so downloads survive leaving the app. Auth is snapshotted into a `BackgroundWorkOrder`; completions are durably logged to a file and replayed into Drift on resume; rotated `ui_login` tokens are written back via `BackgroundTokenRecord`.

> **Single-owner invariant:** on Android the in-process pump is a hard no-op (`pumpDownloads()` returns early on `isAndroidNative`) — the foreground service is the sole downloader. Everywhere else the coordinator pumps on the main isolate.

## Keep-rules and safety nets

`OfflineKeepRule` (per series): `off` (only manually-pinned chapters), `nUnread` (the N oldest unread, N = `keepUnreadCount`), `allUnread`, `all`. Manually-pinned chapters (via **Save to device**) are always kept and never auto-evicted.

`offline_reconciler.dart` + `reconcile_logic.dart` (pure) compute a `ReconcilePlan` (`toDownload` / `toEvict`): `desiredChapterIds()` applies the rule; `applySafetyNets()` evicts unwanted, un-pinned chapters, then a **time net** (older than `keepDays`, default 30) and a **storage cap** (evict oldest until under `storageCapBytes`, default 2 GB). The cap also stops *adding* download candidates once projected bytes would exceed it. Settings live in `offline_settings_providers.dart`.

## On device tab (downloads + management, one surface)

`presentation/offline_files_view.dart` (the **Downloads → On device** tab) is the single place to see and manage on-device downloads. It lists every series with an offline footprint — files present OR an active keep-rule — via `offlineSeriesProvider` over `OfflineDatabase.watchOfflineSeries()`, one Drift join whose `having` keeps rows where `downloaded>0 OR inFlight>0 OR keepRule != off` (so a rule with **nothing downloaded yet** and **hand-saved files with no rule** both appear). Each row shows what's downloaded + its rule; a per-row sliders button (`Icons.tune_rounded`) opens the rule sheet, and long-press multi-selects for bulk actions. Actions live in `offline_download_providers.dart`:

- `changeKeepRule` — set a new rule + reconcile (confirms when the new rule grows the footprint for any selected series).
- `detachKeepRule` — **stop keeping but keep the files**: cancels in-flight chapters, then pins the downloaded set and clears the rule **in one transaction** (so the instant the rule is `off`, every catalog-downloaded chapter is already pinned and can't be evicted by this or a concurrent reconcile), then reconciles. Unfinished chapters are dropped.
- `removeKeepRuleAndDelete` — clear the rule and delete the device copies (server untouched).

## Enable / web

`offlineEnabledProvider` defaults **false**. At startup `initOfflineStorage()` opens the catalog on native, and the storage providers (`offlineDatabaseProvider`, `offlinePathsProvider`, `offlinePageStoreProvider`) plus `offlineEnabledProvider` are overridden to the live instances. On web it returns null, the override never happens, and the storage providers throw `UnimplementedError`. Every caller guards on `offlineEnabledProvider` first, so those throws are unreachable on web.

## Sync + read fallback

`offline_sync.dart` — `OfflineSync` mirrors GraphQL DTOs into the catalog during normal online use, preserving each locally-dirty field (position / read-state / bookmark) over the incoming server value independently — so an offline read is never overwritten by a stale down-sync, yet a server-side read/bookmark set on another client still lands locally while a different field is pending up-sync. `offline_read_fallback.dart` — five wrappers (`libraryWithOfflineFallback`, `mangaWithOfflineFallback`, `chaptersWithOfflineFallback`, `chapterMetaWithOfflineFallback`, `categoriesWithOfflineFallback`): on a network error, if offline is enabled and the catalog has data, they return mapped local rows (categories synthesise a single "Default" so the Library tab still renders). The reader serves pages via `OfflineRepository.localChapterPages(chapterId)` when `deviceState == downloaded`.

## Server-switch guard

The catalog belongs to one server identity at a time. On first connection, Tsumiru creates a UUID in Suwayomi's server-wide global metadata under `tsumiru_server_instance_id`; later connections read that value through `serverInstanceIdProvider`. `offlineCatalogServerId` stores the UUID after a successful metadata sync. The configured scheme, host, and port are only a route: changing them does not change server identity.

The last verified address-to-UUID pair is cached locally so a cold start without network access can still open an already-verified catalog. A new address must connect and return the server UUID before offline writes or download workers start. `offlineActiveProvider` disables metadata sync, progress writes, reconciliation, and both download workers until identity is verified and matches. A legacy unstamped catalog remains readable offline but is not modified until verification succeeds.

A mismatch with catalog data shows a persistent warning in Library and Offline settings. Dismiss parks the old catalog without exposing or modifying it. Clear stops the foreground worker and main-isolate pump, removes their queued work, wipes every catalog table plus page/cover files, and resets the identity. An empty catalog adopts the active identity without prompting.

## UI entry points

- **Chapter list** — `presentation/offline_save_button.dart` (`OfflineSaveButton`): per-chapter save / delete with a state-machine icon (queued / downloading / downloaded / error / save).
- **Manga-details action row** — `presentation/series_offline_button.dart` (`SeriesOfflineButton`): the **Offline** button; opens the keep-rule sheet.
- **Settings → Downloads → Offline** — `presentation/offline_settings_screen.dart`: storage usage, concurrency (1–8), Wi-Fi-only, storage-cap and time-evict toggles.

## Gotchas

- **Android downloads ride entirely on the foreground service.** If `ensureServiceRunning()` can't start (e.g. notification permission denied), chapters queue in Drift but nothing downloads.
- **`_pumping` is a process-wide static.** If the coordinator provider rebuilds mid-drain (a concurrency change, or a token refresh rotating the GraphQL client → repo dependency), the new instance is blocked until the old drain finishes or the app restarts. Pause still reaches the old drain via the persisted flag (captured prefs, read live per chapter); cancelling an in-flight chapter across a rebuild does not. A chapter mid-download when the engine itself rebuilds fails its next page fetch, is marked `error`, and self-heals via the launch requeue.
- **Wi-Fi-only** is enforced when work starts, but a Wi-Fi → mobile switch while the app is backgrounded isn't currently caught.
- **`offlineDatabaseProvider` (and the other storage providers) throw on web** by design — never touch them without the `offlineEnabledProvider` guard.
