# Offline reading

Save chapters to the device and read them with **no server connection**, with automatic fallback to local copies when the server is unreachable. Native-only (Android / desktop); the whole subsystem is inert on web. Lives under `lib/src/features/offline/`.

## On-device catalog

`data/offline_database.dart` — a Drift / SQLite database (`OfflineDatabase`, schemaVersion 3) at `<appSupport>/offline/catalog.sqlite`. Tables:

- `OfflineMangas` — `id` (server manga id) PK; `title`, `thumbnailUrl`, `thumbnailRelPath`, `keepRule` (`OfflineKeepRule`, default `off`), `keepUnreadCount` (default 3).
- `OfflineChapters` — `id` (server chapter id) PK, indexed by `mangaId`; `deviceState` (`OfflineDeviceState`, default `none`), `pageCount`, `bytes`, `pinned`, `downloadedAt`, `serverIsDownloaded`, `progressDirty`, plus read state.
- `OfflineCategories`, `OfflineMangaCategories`, and `OfflinePages` (`(chapterId, pageIndex)` → `relativePath`).

Design notes: there is **no foreign key** from chapters to mangas — a chapter whose server manga is gone becomes `deviceState = orphaned` instead of cascade-deleting. The metadata upserts (`upsertMangaMetadata` / `upsertChapterMetadata`) deliberately exclude device-managed columns (`deviceState`, `bytes`, `thumbnailRelPath`) from `ON CONFLICT UPDATE`, so a metadata sync can never clobber download state.

`data/offline_repository.dart` — `OfflineRepository`, the single interface over Drift (`localChapterPages`, `watchChapterState`, `keepRuleFor`, …). `data/offline_paths.dart` — `OfflinePaths`, pure path arithmetic (`<mangaId>/<chapterId>/<NNN>.<ext>`, forward-slash relative paths). `data/offline_page_store*.dart` — `OfflinePageStore` (abstract) + `IoOfflinePageStore` (writes page bytes to disk).

## Download pipeline

Four layers, all driven through one entry point — **`downloadStarterProvider`** (never call the lower layers directly):

1. `chapter_download_engine.dart` — `ChapterDownloadEngine` downloads one chapter's pages with up to N concurrent workers (N = `OfflineDownloadConcurrency`, default 2), each page retried 3× with backoff. `PageAuthException` → one auth refresh + retry; `PageOfflineException` → stop and leave the run resumable.
2. `offline_download_coordinator.dart` — `OfflineDownloadCoordinator` queues and runs **one chapter at a time** (Komikku model) via the engine; `pumpDownloads()` drains the queue. Process-wide single-flight via a `static _pumping` flag.
3. `offline_download_providers.dart` — the wiring + the public surface: `saveChapterToDevice`, `deleteChapterFromDevice`, `reconcileManga`, `recordReadingProgress`, `pushPendingProgress`, and the state streams (`offlineChapterStateProvider`, `mangaOfflineProgressProvider`, `mangaKeepRuleProvider`, …).
4. `data/background/` — **Android only**: `BackgroundDownloadController` owns a `FlutterForegroundTask` foreground service (its own isolate, `download_task_handler.dart`) so downloads survive leaving the app. Auth is snapshotted into a `BackgroundWorkOrder`; completions are durably logged to a file and replayed into Drift on resume; rotated `ui_login` tokens are written back via `BackgroundTokenRecord`.

> **Single-owner invariant:** on Android the in-process pump is a hard no-op (`pumpDownloads()` returns early on `isAndroidNative`) — the foreground service is the sole downloader. Everywhere else the coordinator pumps on the main isolate.

## Keep-rules and safety nets

`OfflineKeepRule` (per series): `off` (only manually-pinned chapters), `nUnread` (the N oldest unread, N = `keepUnreadCount`), `allUnread`, `all`. Manually-pinned chapters (via **Save to device**) are always kept and never auto-evicted.

`offline_reconciler.dart` + `reconcile_logic.dart` (pure) compute a `ReconcilePlan` (`toDownload` / `toEvict`): `desiredChapterIds()` applies the rule; `applySafetyNets()` evicts unwanted, un-pinned chapters, then a **time net** (older than `keepDays`, default 30) and a **storage cap** (evict oldest until under `storageCapBytes`, default 2 GB). The cap also stops *adding* download candidates once projected bytes would exceed it. Settings live in `offline_settings_providers.dart`.

## Enable / web

`offlineEnabledProvider` defaults **false**. At startup `initOfflineStorage()` opens the catalog on native, and the storage providers (`offlineDatabaseProvider`, `offlinePathsProvider`, `offlinePageStoreProvider`) plus `offlineEnabledProvider` are overridden to the live instances. On web it returns null, the override never happens, and the storage providers throw `UnimplementedError`. Every caller guards on `offlineEnabledProvider` first, so those throws are unreachable on web.

## Sync + read fallback

`offline_sync.dart` — `OfflineSync` mirrors GraphQL DTOs into the catalog during normal online use, preserving locally-dirty read progress over incoming server values (an offline read is never overwritten by a stale down-sync). `offline_read_fallback.dart` — five wrappers (`libraryWithOfflineFallback`, `mangaWithOfflineFallback`, `chaptersWithOfflineFallback`, `chapterMetaWithOfflineFallback`, `categoriesWithOfflineFallback`): on a network error, if offline is enabled and the catalog has data, they return mapped local rows (categories synthesise a single "Default" so the Library tab still renders). The reader serves pages via `OfflineRepository.localChapterPages(chapterId)` when `deviceState == downloaded`.

## UI entry points

- **Chapter list** — `presentation/offline_save_button.dart` (`OfflineSaveButton`): per-chapter save / delete with a state-machine icon (queued / downloading / downloaded / error / save).
- **Manga-details action row** — `presentation/series_offline_button.dart` (`SeriesOfflineButton`): the **Offline** button; opens the keep-rule sheet.
- **Settings → Downloads → Offline** — `presentation/offline_settings_screen.dart`: storage usage, concurrency (1–8), Wi-Fi-only, storage-cap and time-evict toggles.

## Gotchas

- **Android downloads ride entirely on the foreground service.** If `ensureServiceRunning()` can't start (e.g. notification permission denied), chapters queue in Drift but nothing downloads.
- **`_pumping` is a process-wide static.** If the coordinator provider rebuilds mid-drain (e.g. a concurrency change), the new instance is blocked until the old drain finishes or the app restarts.
- **Wi-Fi-only** is enforced when work starts, but a Wi-Fi → mobile switch while the app is backgrounded isn't currently caught.
- **`offlineDatabaseProvider` (and the other storage providers) throw on web** by design — never touch them without the `offlineEnabledProvider` guard.
