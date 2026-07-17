# Manga Details, Chapters & Downloads

(The reader lives in the same feature folder but is documented in [reader.md](reader.md).)

## Key files

| Path | Responsibility |
|---|---|
| `manga_book/data/manga_book/manga_book_repository.dart` | All manga/chapter queries + mutations (get manga, `fetchChapters`, update manga, patch chapter, batch update, delete download, set meta, get pages) |
| `manga_book/data/downloads/downloads_repository.dart` | Download queue: holds query + subscription clients; start/stop/clear/enqueue/dequeue/reorder + the live status stream |
| `manga_book/domain/manga/manga_model.dart` | `MangaDto` (typedef), `MangaMeta` (freezed), `MangaMetaKeys` |
| `manga_book/domain/chapter/chapter_model.dart` | `ChapterDto` (typedef); `.index` = `sourceOrder` |
| `manga_book/domain/chapter/chapter_download_presets.dart` | `DownloadPreset` enum + `chaptersToQueueForPreset()` (pure, testable) |
| `manga_book/domain/downloads/downloads_model.dart` | `DownloadDto`, `DownloaderState`, `DownloadState`, `DownloadUpdateType` (typedefs) |
| `.../manga_details/manga_details_screen.dart` | Root; owns `selectedChapters`; switches AppBar normal/multi-select |
| `.../manga_details/controller/manga_details_controller.dart` | All manga-details providers |
| `.../manga_details/widgets/{small,big}_screen_manga_details.dart` | Phone / tablet layouts |
| `.../manga_details/widgets/chapter_list_tile.dart` | Chapter row + trailing `DownloadStatusIcon` |
| `.../manga_details/widgets/chapter_grid_tile.dart` | Compact number tile for the grid view (read/downloaded/bookmark/in-progress states) |
| `.../manga_details/widgets/chapter_list_mode_toggle.dart` | List/grid segmented toggle in the chapter-count header |
| `.../manga_details/widgets/chapter_download_presets_button.dart` | Bulk-download presets (operates on the **unfiltered** list) |
| `.../manga_details/widgets/manga_chapter_{organizer,filter,sort,display}.dart` | Filter/Sort/Display sheet (tri-state + scanlator radio; sort radios; title-vs-number display) |
| `manga_book/widgets/chapter_actions/multi_chapters_actions_bottom_app_bar.dart` | Multi-select action bar |
| `manga_book/widgets/download_status_icon.dart` | Inline per-chapter download progress/state |
| `.../downloads/downloads_screen.dart` (+ `controller/`, `widgets/`) | Standalone queue screen |

## Manga details

`MangaDetailsScreen(mangaId, categoryId?)` watches `mangaWithIdProvider`, `mangaChapterListProvider` (**fetched via the `fetchChapters` mutation**, keepAlive), and `mangaChapterListWithFilterProvider`. First build fires `refresh()`; pull-to-refresh wired. AppBar has normal vs multi-select modes; FAB points to `firstUnreadInFilteredChapterListProvider`. On pop, invalidates `categoryMangaListProvider(categoryId)`. Phone = `CustomScrollView` + `SliverList`; tablet = end-drawer organizer.

## Chapters & actions

- Filtering/sorting is client-side in `mangaChapterListWithFilterProvider`. Filter/sort/display state is **global** (SharedPreferences); the **scanlator** filter is **per-manga** (server meta `flutter_scanlator`). `ChapterSort`: `source`, `fetchedDate`, `uploadDate`, `chapterNumber`, `alphabetical` (enum indices are persisted — append new values last). `ChapterDisplay` (`sourceTitle` | `chapterNumber`) swaps the tile title between `chapter.name` and a formatted "Chapter N" (Komikku-style `#.###` number formatting); offline-fallback rows fake `chapterNumber` from `chapterIndex`, so number display/sort degrade to source order there.
- **List vs grid** (`ChapterListMode`) is **per-manga** (server meta `flutter_chapterListMode`, default list) via `mangaChapterListModeProvider`. Grid tiles show the chapter number only (`ChapterGridTile.label`: whole numbers drop `.0`, unparsed fall back to `#sourceOrder`); states = dim read, gradient dot downloaded, bookmark icon, gradient ring + page marker on the in-progress chapter. Same tap/long-press/right-click semantics as list rows.
- Tile: tap → reader; long-press / right-click → multi-select.
- Multi-select bar: bookmark add/remove, mark-previous-read, mark read (`lastPageRead: 0`), mark unread, download, delete — then clears selection + refreshes.
- **Bulk-download presets** operate on the **full unfiltered** list: sort by `chapterNumber` asc, find highest read, walk forward collecting un-downloaded IDs ("Next N" skips downloaded).
- Single vs bulk: `SingleChapterActionIcon` → `putChapter`; `MultiChaptersActionIcon` → `modifyBulkChapters` (`UpdateChapters`).

## Downloads

Two-source state: `downloadStatusProvider` polls `GetDownloadStatus` for the initial snapshot; `downloadUpdatesProvider` opens a `DownloadStatusChanged` subscription (`graphQlSubscriptionClientProvider`, `maxUpdates: 150`). `downloadsMapProvider` (`Map<int, DownloadDto>` keyed by chapter id) merges deltas: `DEQUEUED`/`FINISHED` remove; others upsert. `downloadsChapterIdsProvider` sorts by `position`. Each `DownloadProgressListTile` and inline `DownloadStatusIcon` watches `downloadsFromIdProvider(chapterId)` (a `.select`) so tiles rebuild independently. `DownloadStatusIcon` triggers a chapter-list refresh on `FINISHED` via `Future.microtask`.

## Gotchas

- **Bottom inset for the multi-select bar** must be read from `View.of(context).viewPadding.bottom / devicePixelRatio` — inside the shell nav, `MediaQuery` padding/viewPadding report 0 for the bottom-sheet's descendants. (Upstream PR #381.)
- **`fetchChapters` is a mutation** — it triggers a source fetch, not a DB read. Use `query$Chapters` for a local-only lookup.
- **Download presets use the unfiltered list** and compute from the highest **read** chapter by `chapterNumber`, independent of UI sort.
- **Scanlator "no filter" sentinel is the string `"flutter_scanlator"`**, not `null`.
- **`DownloadStatusIcon` `FINISHED` refresh uses `Future.microtask`** — removing it causes "setState during build".
- **`downloadsMapProvider` throws `UnimplementedError` on an unknown `DownloadUpdateType`** — a new server state crashes the subscription listener until handled.
- **Two distinct GraphQL clients** (query + subscription) — auth/interceptor changes must touch both in `global_providers.dart`.
- **`mangaChapterListProvider` is keepAlive** — reflect chapter changes via `updateChapter()` or `ref.invalidate`, not a plain rebuild.
- **`ChapterDto.index` is `sourceOrder`**, not list position.
