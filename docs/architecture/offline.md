# Offline reading

Save chapters to the device and read them with **no server connection**, with automatic fallback to local copies when the server is unreachable. Native-only (Android / desktop); the whole subsystem is inert on web. Lives under `lib/src/features/offline/`.

## On-device catalog

`data/offline_database.dart` — a Drift / SQLite database (`OfflineDatabase`, schemaVersion 7) at `<appSupport>/offline/catalog.sqlite`. Tables:

- `OfflineMangas` — `id` (server manga id) PK; `title`, `thumbnailUrl`, `thumbnailRelPath`, `keepRule` (`OfflineKeepRule`, default `off`), `keepUnreadCount` (default 3).
- `OfflineChapters` — `id` (server chapter id) PK, indexed by `mangaId`; `deviceState` (`OfflineDeviceState`, default `none`), `pageCount`, `bytes`, `pinned`, `downloadedAt`, `serverIsDownloaded`, read state, and three independent "not yet pushed" flags — `progressDirty` (position), `readStateDirty` (isRead), `bookmarkDirty` (isBookmarked). Each field syncs under its own flag so a position-only write can never push a stale isRead (the ch-99 un-read loop) and a read/bookmark change set elsewhere still lands locally while another is pending.
- `OfflineCategories`, `OfflineMangaCategories`, and `OfflinePages` (`(chapterId, pageIndex)` → `relativePath`).

Design notes: there is **no foreign key** from chapters to mangas — a chapter whose server manga is gone becomes `deviceState = orphaned` instead of cascade-deleting. The metadata upserts (`upsertMangaMetadata` / `upsertChapterMetadata`) deliberately exclude device-managed columns (`deviceState`, `bytes`, `thumbnailRelPath`) from `ON CONFLICT UPDATE`, so a metadata sync can never clobber download state.

`data/offline_repository.dart` — `OfflineRepository`, the single interface over Drift (`localChapterPages`, `watchChapterState`, `keepRuleFor`, …). `data/offline_paths.dart` — `OfflinePaths`, pure path arithmetic (`<mangaId>/<chapterId>/<NNN>.<ext>` final, `<mangaId>/<chapterId>.part/` staging, forward-slash relative paths). `data/offline_page_store*.dart` — `OfflinePageStore` (abstract) + `IoOfflinePageStore` (writes page bytes to disk).

## Chapters are atomic

A chapter is **absent or whole** — never a short directory that a page count would read as finished. Pages accumulate in `<mangaId>/<chapterId>.part/`, which nothing else on the device looks at, and the chapter becomes visible in **one directory rename** once every page is present. This is the Komikku model (`Downloader.kt` `_tmp` dirs), with one addition Komikku doesn't need: our filesystem isn't the only source of truth, so a catalog has to agree with it.

- **`chapter_manifest.dart`** — `{generation, indices}`, written into staging before the first page. It is the only thing on disk that knows how many pages a chapter should have; the catalog's `pageCount` can't serve, because it defaults to 0 and a metadata sync rewrites it from the server. Completeness is "one file per listed index", never a count.
- **`chapter_commit.dart`** — `commitStagedChapter()` is the ONE place a download becomes visible: re-read the row (must not be `none`, manifest generation must still match), rename staging into place, then insert every page row and mark `downloaded` in one transaction. `ChapterFileLock` serializes commit, delete, eviction, and migration per chapter, which is what stops a delete slipping between the check and the rename.
- **Single committer.** Only the main isolate commits. The Android foreground service and the WorkManager catch-up run *fill staging*; they have no Drift access, so they can't perform the row check a commit requires. The FGS worker's terminal event triggers the commit on the main isolate; catch-up chapters commit at the next launch (same user-visible timing as before — adoption already happened at replay).
- **Recovery** (`recoverChaptersOnDisk`) runs at every launch on every platform — through the worker's replay on Android, through `initOfflineDownloads` elsewhere. It walks the directories that exist (bounded by what's downloaded, unlike the chapter table) and settles each against its row: a complete directory under a non-`downloaded` row is adopted (the rename landed, its transaction didn't); anything under a `none` or missing row is deleted; a directory whose manifest generation no longer matches the row is dropped as superseded; staging is committed or left to resume.
- **Legacy.** Directories written before this carry no manifest. A `downloaded` row is grandfathered and trusted; anything else is cleared for one re-download.
- **No fsync.** Removing the per-page `flush: true` was the point: an fsync per page, hundreds per webtoon chapter times concurrent workers, was what drove downloads to 30–80% CPU. Only the manifest and the completion log still sync. Power loss can still leave truncated bytes inside a committed chapter — Komikku-identical exposure, and the reason to prefer checksums-on-read over bringing fsync back.

## Download pipeline

Four layers, all driven through one entry point — **`downloadStarterProvider`** (never call the lower layers directly):

1. `chapter_download_engine.dart` — `ChapterDownloadEngine` downloads one chapter's pages with up to N concurrent workers (N = `OfflineDownloadConcurrency`, default 2), each page retried 3× with backoff. `PageAuthException` → one auth refresh + retry; `PageOfflineException` → stop and leave the run resumable.
2. `offline_download_coordinator.dart` — `OfflineDownloadCoordinator` queues and runs **one chapter at a time** (Komikku model) via the engine; `pumpDownloads()` drains the queue. Process-wide single-flight via a `static _pumping` flag. The coordinator and engine providers are **keep-alive**: nothing watches them (all consumers are one-shot reads), and an auto-dispose Ref dies at the first async gap — under Riverpod 3 its call-time reads then throw `UnmountedRefException`, which silently killed launch resume and the desktop pump.
3. `offline_download_providers.dart` — the wiring + the public surface: `saveChapterToDevice`, `deleteChapterFromDevice`, `reconcileManga`, `recordReadingProgress`, `recordReadState` (offline-aware write-through for mark-read/unread), `pushPendingProgress`, and the state streams (`offlineChapterStateProvider`, `mangaOfflineProgressProvider`, `mangaKeepRuleProvider`, …). The per-chapter progress arc reads `offlineDownloadProgressProvider` (in-memory, fed by whichever downloader is running) rather than counting page rows — those all appear at once when a chapter commits.
4. `data/background/` — **Android only**: `BackgroundDownloadController` owns a `FlutterForegroundTask` foreground service (its own isolate, `download_task_handler.dart`) so downloads survive leaving the app. Auth is snapshotted into a `BackgroundWorkOrder`; rotated `ui_login` tokens are written back via `BackgroundTokenRecord`. The worker fills staging and records terminal / adoption / tombstone / timeout entries in the completion log — per-page lines are gone, since they were a second fsync on every page and the manifest already says what complete means.

> **Single-owner invariant:** on Android the in-process pump is a hard no-op (`pumpDownloads()` returns early on `isAndroidNative`) — the foreground service and scheduled worker share exclusive download ownership. Everywhere else the coordinator pumps on the main isolate.

## Android service recovery

A service start is attempted regardless of app visibility. An actual refusal records `offlineDownloadsStalled` as `background`; other start failures record `service`. Automatic triggers, including forced server-recovery calls, cannot repeat a failed start. Returning to the app, visible launch, and explicit Retry/Resume/enqueue grant a new attempt. A recovery arriving during startup survives that attempt's late failure. Real server backoff is brought within 15 seconds on return.

The On device banner and navigation badge reflect the pending queue, explicit pause, current network restrictions and persisted stall. The stall notification has its own ID, so recovery cannot cancel chapter-error notifications. Successful startup, empty work, pause and catalog clear clear the stall. Notification settings do not suppress the in-app explanation.

Work orders carry attempt identities. Publication, worker admission and failed-start cleanup share an admission lock. Workers acquire download ownership before rereading and claiming the current order. Cleanup cannot remove an accepted worker's credentials or a newer attempt. Cancellation updates the durable order; pause invalidates it.

Download and admission ownership use separate SQLite databases with held immediate transactions. Connections in different isolates cannot own the same lock; process exit releases ownership without stale-file stealing. Yield requests remain separate marker files.

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

`offline_sync.dart` — `OfflineSync` mirrors GraphQL DTOs into the catalog during normal online use, preserving each locally-dirty field (position / read-state / bookmark) over the incoming server value independently — so an offline read is never overwritten by a stale down-sync, yet a server-side read/bookmark set on another client still lands locally while a different field is pending up-sync. `offline_read_fallback.dart` — five wrappers (`libraryWithOfflineFallback`, `mangaWithOfflineFallback`, `chaptersWithOfflineFallback`, `chapterMetaWithOfflineFallback`, `categoriesWithOfflineFallback`): on a network error, if offline is enabled and the catalog has data, they return mapped local rows (categories synthesise a single "Default" so the Library tab still renders). **The offline library lists only series with downloaded files** (2026-07-29, Aaron reversing the June 21 "whole library browsable offline" decision — people go offline to read, not to browse metadata); everything else is managed via Downloads → On device. Per-series meta (reader mode/orientation) and the Last Read sort key are mirrored into the catalog on every library sync so downloaded series read identically offline. The reader serves pages via `OfflineRepository.localChapterPages(chapterId)` when `deviceState == downloaded`.

Fallback timing: a request that *hangs* (dead keep-alive socket in airplane mode, a proxy edge whose origin is down) is not a network error until it times out, so fallback-capable reads cap their fetch at `kOfflineFallbackFetchTimeout` (15s) whenever the catalog has data — without the cap, the default timeout-and-retry window (~90s per provider, serialized across the library screen's providers) left the library blank for minutes. Connections that can't even *establish* within `kConnectionEstablishTimeout` (8s, `TimeoutHttpClient`) fail immediately everywhere. The library loading state (`offline_view_loading.dart`) offers a **View offline** button when a catalog exists; it sets `viewOfflineNowProvider` (session-only), which every fallback wrapper honors as `offlineFirst` — serve the catalog, skip the network. Any manual refresh clears the pin.

## Covers offline

Covers are rendered by `ServerImage` from HTTP cache, not stored in the offline file tree. They route (by URL, `isCoverImagePath`) to a dedicated cache manager (`lib/src/widgets/cover_cache/`) rooted in application support — durable across reboots and OS cache cleanup, 5000 entries, 90-day idle eviction — instead of the default manager's 200-file temp-dir cache shared with reader pages (which is why offline covers used to be mostly broken tiles). `OfflineCoverWarmer` tops up any missing library covers on each online library load, so a series never scrolled past still has art offline.

## Server-switch guard

The catalog belongs to one server identity at a time. On first connection, Tsumiru creates a UUID in Suwayomi's server-wide global metadata under `tsumiru_server_instance_id`; later connections read that value through `serverInstanceIdProvider`. `offlineCatalogServerId` stores the UUID after a successful metadata sync. The configured scheme, host, and port are only a route: changing them does not change server identity.

The last verified address-to-UUID pair is cached locally so a cold start without network access can still open an already-verified catalog. A new address must connect and return the server UUID before offline writes or download workers start. `offlineActiveProvider` disables metadata sync, progress writes, reconciliation, and both download workers until identity is verified and matches. A legacy unstamped catalog remains readable offline but is not modified until verification succeeds.

A mismatch with catalog data shows a persistent warning in Library and Offline settings. Dismiss parks the old catalog without exposing or modifying it. Clear stops the foreground worker and main-isolate pump, removes their queued work, wipes every catalog table plus page/cover files, and resets the identity. An empty catalog adopts the active identity without prompting.

## UI entry points

- **Chapter list** — `presentation/offline_save_button.dart` (`OfflineSaveButton`): per-chapter save / delete with a state-machine icon (queued / downloading / downloaded / error / save).
- **Manga-details action row** — `presentation/series_offline_button.dart` (`SeriesOfflineButton`): the **Offline** button; opens the keep-rule sheet.
- **Settings → Downloads → Offline** — `presentation/offline_settings_screen.dart`: storage usage, concurrency (1–8), Wi-Fi-only, storage-cap and time-evict toggles.

## Gotchas

- **Android service starts can be refused.** The scheduled worker continues published queue obligations without starting a foreground service, subject to Android scheduling and current constraints.
- **`_pumping` is a process-wide static.** If the coordinator provider rebuilds mid-drain (a concurrency change, or a token refresh rotating the GraphQL client → repo dependency), the new instance is blocked until the old drain finishes or the app restarts. Pause still reaches the old drain via the persisted flag (captured prefs, read live per chapter); cancelling an in-flight chapter across a rebuild does not. A chapter mid-download when the engine itself rebuilds fails its next page fetch, is marked `error`, and self-heals via the launch requeue.
- **Wi-Fi-only** is checked by both workers during a run; losing the permitted connection cancels the current transfer and leaves partial files resumable.
- **Deleting files is best-effort.** A locked or unwritable directory can outlive the delete that cleared its row, which is why recovery checks the committed manifest's generation instead of trusting a complete directory.
- **Migration copies, then commits, then drops the source.** A bare rename would destroy the source before the target's catalog write landed, and a crash in that window leaves a complete directory under a `none` row — which recovery would rightly delete as a user delete, taking the only copy.
- **`offlineDatabaseProvider` (and the other storage providers) throw on web** by design — never touch them without the `offlineEnabledProvider` guard.

## Scheduled queue continuation

User enqueue publishes exact chapter IDs and download generations, then saves the notification worker's endpoint/auth configuration and reconciles its periodic schedule before attempting a foreground service start. This works with notifications, automatic catch-up and keep rules off. Publication errors surface to the user without preventing a permitted service start.

One periodic job serves notifications, keep-rule catch-up and the manually queued downloads. Its constraints permit every active activity; each activity checks its own Wi-Fi and charging policy before running. Queue demand disappears on pause, cancellation or generation-matching terminal completion. Publication and schedule reconciliation share a SQLite admission lock, so an older cancellation cannot remove a new enqueue's schedule.

The scheduled executor processes queued generations before keep-rule work, sharing ten completions and a seven-minute deadline. Complete staging repairs a missing terminal record without spending a new completion slot. Queue obligations use separate, generation-scoped server-fetch and device-download retry budgets; cancellation and transient failures spend neither. Keep rules cannot retry a chapter owned by the published queue. Keep-rule server-fetch asks count as a strike at most once an hour (`serverFetchAskedAt`), five strikes give up on the chapter, a give-up expires after a day, and the budget clears as soon as the server reports the chapter downloaded. Existing staged files count toward the storage cap. Matching-generation partial chapters may finish after the cap is reached; fresh chapters wait.

Both background workers hold one SQLite write transaction for download/log ownership. Pause, cancellation, eviction, migration, reader repair, catalog clear and identity changes wait for that ownership before modifying files. Workers check the yield marker every 250 ms and persisted controls every two seconds, latch cancellation before aborting HTTP, and release ownership after writes stop. A yielded service must finish native shutdown before a replacement starts; handoff retries retain explicit user intent while startup or another control is active. The main isolate remains the only catalog committer.

Endpoint and credential changes revoke a persisted authorization epoch before taking ownership. Saved service orders and scheduled worker configurations carry that epoch. A successful verification of the current endpoint can authorize the new epoch; an old captured configuration stays invalid even if the address and catalog UUID are unchanged. Each background run also checks the live server UUID before fetching chapter data. Foreground refresh admission stays closed throughout credential transitions, and serialized credential writes drain before a new login is saved.

Android service timeout writes a durable timeout record while ownership is held, after active writes stop. Replay restores the budget explanation without changing chapter state. Visible launch or resume still grants a recovery attempt; a historical timeout does not consume it.
