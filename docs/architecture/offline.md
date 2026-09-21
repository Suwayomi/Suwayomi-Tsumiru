# Offline reading

Save chapters to the device and read them with **no server connection**, with automatic fallback to local copies when the server is unreachable. Native-only (Android / desktop); the whole subsystem is inert on web. Lives under `lib/src/features/offline/`.

## On-device catalog

`data/offline_database.dart` — a Drift / SQLite database (`OfflineDatabase`, schemaVersion 17). The established legacy account keeps `<appSupport>/offline/catalog.sqlite`; new accounts use `<appSupport>/offline/accounts/<catalogueId>/catalog.sqlite`. Completed migrations retain their account folder. Tables:

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

`presentation/offline_files_view.dart` (the **Downloads → On device** tab) is the single place to see and manage on-device downloads. It lists every series with an offline footprint — saved, pending or failed chapters, or an active keep-rule — via `offlineSeriesProvider` over `OfflineDatabase.watchOfflineSeries()`, one Drift join whose `having` keeps rows where `downloaded>0 OR inFlight>0 OR failed>0 OR keepRule != off` (so a rule with **nothing downloaded yet** and **hand-saved files with no rule** both appear). Each row shows saved, downloading and failed counts with its rule; a manual series whose only chapter failed remains visible for retry. A per-row sliders button (`Icons.tune_rounded`) opens the rule sheet, and long-press multi-selects for bulk actions. Actions live in `offline_download_providers.dart`:

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

## Server and account ownership

`offlineActiveProvider` admits writes only for the verified active catalogue. The configured host and port are a route, not an identity: LAN/remote failover preserves ownership, while a new unverified address cannot start offline writers. The last verified address/identity pair permits an offline cold start. Legacy storage remains readable without being reassigned to an unverified account.

UI Login binds the verified account and catalogue ID to its credentials. `offline_bootstrap_io.dart`, `account_storage_paths.dart` and `account_storage_migration_io.dart` resolve the catalogue to its claimed root or account directory. `.account-root-id` records the root identity, and owner and completion markers prevent another account from claiming it. `offlineAccountScopedKey` records the physical layout for background workers; account preference keys remain scoped by identity. Switching accounts drains storage operations, replaces the database/page-store providers and worker configuration together, and keeps the previous catalogue inactive. Server downloads remain shared server files; device files, library metadata, read state and keep rules follow the active account.

Account settings can remove a retained inactive catalogue. Removal clears its data while retaining the cleared marker and ownership lock files, so later login cannot import the old legacy root again or create a second lock beside one still in use. Identity changes, catalogue removal and download workers use the same ownership protocol. See `offline_runtime_storage.dart`, `account_catalogue_repository_io.dart` and `account_storage_migration_io.dart`.

When a UI Login server gains account support, Suwayomi assigns its old data and
catalogue metadata to user 1. For that same catalogue, Tsumiru atomically upgrades
an existing `legacy` owner marker to `1`, whether storage is at the root or in an
account folder. Other owner changes and a return from `1` to `legacy` are rejected.

Interrupted migration is deferred until the app is usable. `AccountSessionStorage.recover()` publishes progress and failure state for the shell banner, supports retry, and cancels on identity replacement. Catalogue reconciliation preserves both SQLite snapshots, merges missing records, and asks the user to choose conflicting reading state. Saved choices are reused only while both states still match. Recovering legacy reading state copies its timestamp and pending flags; recovery does not enqueue already-synced progress as a new read. Recovery moves files on the same filesystem; fallback copying and duplicate verification run in a cancellable isolate. Originals are removed only after verified retention. Root removal excludes nested account folders and shared controls.

## UI entry points

- **Chapter list** — `presentation/offline_save_button.dart` (`OfflineSaveButton`): per-chapter save / delete with a state-machine icon (queued / downloading / downloaded / error / save).
- **Manga-details action row** — `presentation/series_offline_button.dart` (`SeriesOfflineButton`): the **Offline** button; opens the keep-rule sheet.
- **Settings → Downloads → Offline** — `presentation/offline_settings_screen.dart`: storage usage, concurrency (1–8), Wi-Fi-only, storage-cap and time-evict toggles.

## Gotchas

- **Android service starts can be refused.** The scheduled worker continues published queue obligations without starting a foreground service, subject to Android scheduling and current constraints.
- **`_pumping` is process-wide.** A replacement coordinator cannot drain concurrently with an existing one. Persisted pause and captured session checks also stop an active attempt before subsequent pages or commit. Authentication/network holds resume without resetting a chapter's retry budget; terminal failures require explicit retry.
- **Wi-Fi-only** is checked by both workers during a run; losing the permitted connection cancels the current transfer and leaves partial files resumable.
- **Deleting files is best-effort.** A locked or unwritable directory can outlive the delete that cleared its row, which is why recovery checks the committed manifest's generation instead of trusting a complete directory.
- **Migration copies, then commits, then drops the source.** A bare rename would destroy the source before the target's catalog write landed, and a crash in that window leaves a complete directory under a `none` row — which recovery would rightly delete as a user delete, taking the only copy.
- **`offlineDatabaseProvider` (and the other storage providers) throw on web** by design — never touch them without the `offlineEnabledProvider` guard.

## Scheduled queue continuation

User enqueue publishes exact chapter IDs and download generations, then saves the notification worker's endpoint/auth configuration and reconciles its periodic schedule before attempting a foreground service start. This works with notifications, automatic catch-up and keep rules off. Publication errors surface to the user without preventing a permitted service start.

One periodic job serves notifications, keep-rule catch-up and the manually queued downloads. Its constraints permit every active activity; each activity checks its own Wi-Fi and charging policy before running. Queue demand disappears on pause, cancellation or generation-matching terminal completion. Publication and schedule reconciliation share a SQLite admission lock, so an older cancellation cannot remove a new enqueue's schedule.

The scheduled executor processes queued generations before keep-rule work, sharing ten completions and a seven-minute deadline. Complete staging repairs a missing terminal record without spending a new completion slot. Queue obligations use separate, generation-scoped server-fetch and device-download retry budgets; cancellation and transient failures spend neither. Keep rules cannot retry a chapter owned by the published queue. Keep-rule server fetches retain the shared five-request limit per chapter generation. A chapter already downloaded on the server can proceed to its separate device-download budget. Existing staged files count toward the storage cap. Matching-generation partial chapters may finish after the cap is reached; fresh chapters wait.

Both background workers hold one SQLite write transaction for download/log ownership. Pause, cancellation, eviction, migration, reader repair, catalog clear and identity changes wait for that ownership before modifying files. Workers check the yield marker every 250 ms and persisted controls every two seconds, latch cancellation before aborting HTTP, and release ownership after writes stop. A yielded service must finish native shutdown before a replacement starts; handoff retries retain explicit user intent while startup or another control is active. The main isolate remains the only catalog committer.

Endpoint and credential changes revoke a persisted authorization epoch before taking ownership. Saved service orders and scheduled worker configurations carry that epoch. A successful verification of the current endpoint can authorize the new epoch; an old captured configuration stays invalid even if the address and catalog UUID are unchanged. Each background run also checks the live server UUID before fetching chapter data. Foreground refresh admission stays closed throughout credential transitions, and serialized credential writes drain before a new login is saved.

Android service timeout writes a durable timeout record while ownership is held, after active writes stop. Replay restores the budget explanation without changing chapter state. Visible launch or resume still grants a recovery attempt; a historical timeout does not consume it.

Offline category schema version 17 stores `isDefaultCategory` separately from
`autoAdd`. Upgrading older catalogues marks ID 0 as the special category; automatic
assignment preferences are refreshed by the next category sync. Account category
mirrors retain nonzero default IDs for offline tab counts.

## Permission and retry ownership

`offline_download_permission.dart` separates a download-permission pause from the user's pause setting. Foreground access must be settled and current; background workers verify account capability and the download grant before each chapter/page-list or server enqueue. Missing or malformed responses hold work. GraphQL errors take precedence over partial data, and a known permission denial wins over concurrent authentication or network failures.

`CatchupStateStore` saves a catalogue-specific permission record with a denial revision under the dedicated `.bg_permission` lock. Workers may record denial but cannot clear it. A foreground restoration can clear the pause only if its captured revision still matches, so a slow successful check cannot overwrite a newer denial. Denial preserves completed files and marks the owned unfinished attempt failed. Account changes and newer chapter generations reject late results.

Authentication failures, network failures and unavailable permission checks leave unfinished work resumable. HTTP client connection errors use the same offline hold as socket errors and timeouts. The Android service stops on an auth hold and uses restart backoff without reporting a network outage. Permission failures and exhausted retry budgets are terminal; restoring permission does not silently retry failed chapters. Explicit retry resets the selected chapter's attempts.

`background_completion_log.dart` replays successful catch-up adoption into an absent or metadata-only generation-zero row before file recovery. Failed adoptions carry `error` or `permissionDenied` plus metadata, so a chapter can appear in the failed list without invented files. Existing completed copies, deletion markers and newer generations take precedence. Moving a downloaded chapter to another source also increments the cleared source generation.

`offline_chapter_catchup.dart` adopts worker obligations before foreground reconciliation. Matching-generation server-fetch counts transfer using the larger of the worker and catalogue counts; obligations with missing chapter metadata stay in the ledger until metadata arrives. Permission holds and unavailable ownership leave the ledger intact. Backfill records pending chapters before attempting them, including work beyond one run's allowance, so auth/network holds cannot disappear behind a completed backfill marker.

Foreground-service messages carry the originating catalogue ID, authorization epoch and attempt ID. `background_download_controller.dart` rejects unowned or mismatched events before dispatch and rechecks identity when queued mutations execute and after asynchronous work. Chapter generation remains a separate check against deletion or retry of the same chapter.

Retry ledgers are stored per catalogue. Identity changes reload preferences after acquiring the outgoing catalogue’s ownership lock before preserving its ledger. A worker that still owns that lock saves accepted attempts before honouring an authorization change; it then stops issuing requests. Server and device retry budgets transfer between queued downloads, keep rules and foreground reconciliation using matching chapter generations and the larger recorded count.

Adoption publishes the refreshed work specification before clearing the transferred ledger. Failed or skipped publication leaves the ledger available for another adoption. Manual save checks the original chapter generation before pinning or resetting retries, and starts only the resulting queued generation. Eviction rechecks generation, pin and keep-rule state before deleting files. Foreground startup notices a changed denial revision even if the visible account grant remains unchanged.
