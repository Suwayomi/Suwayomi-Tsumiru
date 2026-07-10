# Library

## Purpose

Displays the user's saved manga. Fetches the full library once from the server
(`libraryMangaListProvider`), then applies all filtering, sorting, search, and
grouping entirely on the client. View state persists to SharedPreferences.

## Key files

| Path | Responsibility |
|---|---|
| `features/library/data/category_repository.dart` | Category CRUD/reorder; visible category list |
| `features/library/data/graphql/query.graphql` | `AllCategories`, `LibraryManga` (full-library fetch), category mutations |
| `.../library/controller/library_controller.dart` | All library providers: full fetch, filter, sort, display mode, query, badge toggles |
| `.../library/controller/library_manga_list.dart` | `libraryMangaListProvider` (single full fetch) + per-category and grouped partition providers |
| `.../library/controller/library_grouping.dart` | `groupLibrary()` (pure); `libraryGroupedTabsProvider`; `libraryGroupTypeProvider` |
| `.../library/library_screen.dart` | Tab bar, AppBar search + filter, tablet end-drawer; routes BY_DEFAULT vs grouped modes |
| `.../library/category_manga_list.dart` | Per-tab grid/list/descriptive-list/cover-only; multi-select action bar |
| `.../library/widgets/library_manga_organizer.dart` | 4-tab organizer sheet (Filter / Sort / Display / Group) |
| `.../library/widgets/library_manga_filter.dart` | Filter tab: tri-state filters, category and tag include/exclude dialogs, per-tracker filter |
| `.../library/domain/library_search_query.dart` | Search DSL parser/evaluator (`tag:`/`genre:`/`rating:` metatags, quotes, `-` negation) |
| `.../library/widgets/library_manga_sort_tile.dart` | Sort tab: sort key + direction |
| `.../library/widgets/library_manga_display.dart` | Display tab: display mode, portrait/landscape column sliders, badge toggles, tab toggles |
| `.../library/widgets/library_manga_group.dart` | Group tab: grouping mode radio list |
| `.../category/...` | Edit-category screen, tiles, dialogs, create FAB |
| `lib/src/widgets/manga_cover/providers/manga_cover_providers.dart` | Badge/display providers shared with browse |
| `features/library/domain/library_group.dart` | `LibraryGroup` constants; `kDefaultLibraryGroupType`; `statusOrder` |
| `features/library/domain/track_status.dart` | `kTrackStatusInfo`, `trackStatusOrder`, `trackStatusLabel` |
| `features/offline/data/offline_download_providers.dart` | Full-library metadata cache for offline mode (Task 0b) |

## Data flow

1. `libraryMangaListProvider` — single `LibraryManga` GraphQL fetch returning ALL
   in-library manga with categories, track records, and offline metadata. In offline
   mode falls back to the locally persisted metadata cache (Task 0b).
2. `categoryMangaListWithQueryAndFilterProvider(categoryId)` — partitions the full
   library list to the given category, then applies `applyMangaFilter` + `applyMangaSort`
   + text query. Used by `CategoryMangaList` in BY_DEFAULT mode.
3. `groupedMangaListWithQueryAndFilterProvider(mangaIds)` — same filter/sort pipeline
   over an arbitrary manga-id set; used by grouped-mode tabs.
4. `libraryGroupedTabsProvider` — combines the full list + `libraryGroupTypeProvider` +
   visible categories into `List<GroupedTab>` via `groupLibrary()`.

**`applyMangaFilter`** — eight tri-state `bool?` filters ANDed (`null`=off,
`true`/`false` via XOR-style tri-state): unread, downloaded, completed, started,
bookmarked, onDevice (offline), lewd, per-tracker (one filter per logged-in tracker).
Category include/exclude is a separate bool-guarded set-membership filter; user-tag
include/exclude works the same way, but include is OR (has any selected tag) since a
manga carries many tags. Minimum personal star rating is a separate `int` threshold.

**Search DSL** (`LibrarySearchQuery`) — the AppBar query is parsed once per pipeline
run into AND-ed terms. Plain words match title/author/genre (substring); `key:value`
tokens match a field: `tag:` (exact, case-insensitive), `genre:`/`author:`/`artist:`/
`title:` (substring), `unread:`/`downloaded:` (bool), `rating:` (int with optional
`>=`/`<=`/`>`/`<`). Multi-word values quote (`tag:"slice of life"`), a leading `-`
negates, and an unrecognized key falls back to plain text (so `Re:Zero` still works).
Follows Mihon/Komikku library-search conventions. Pure + unit-tested
(`test/src/features/library/library_search_query_test.dart`); `MangaDto.query()` and
`MangaDto.filterFields` bridge it to the GraphQL type.

**`applyMangaSort`** — `MangaSort` x direction: `alphabetical`, `unread`, `dateAdded`,
`lastUpdated`, `lastChapterDate`, `totalChapters`, `lastRead`, `random` (stable
per-session seed), `trackerScore` (normalised 0–10 across scales).

## Display modes

| Mode | Widget | Notes |
|---|---|---|
| `grid` | `MangaCoverGridTile` | Width-based auto-columns or fixed count |
| `list` | `MangaCoverListTile` | Fixed itemExtent 96 |
| `descriptiveList` | `MangaCoverDescriptiveListTile` | Fixed itemExtent 176 |
| `coverOnly` | `MangaCoverGridTile(showTitle: false)` | Same grid delegate as grid; distinct icon (`view_comfy_rounded`) |

Portrait and landscape column counts persisted separately
(`libraryPortraitColumnsProvider` / `libraryLandscapeColumnsProvider`). When count
is 0 the width-based auto-delegate (`mangaCoverGridDelegate`, default 192 px) is used.

## Badges

`downloadedBadge` (default **false**), `unreadBadge` (default **true**),
`languageBadge`, `localBadge`, `sourceBadge` — all toggled in the Display tab.
`useLangIcon` swaps the language text badge for the source icon when language badge
is on. Providers live in `manga_cover/providers/`, shared with browse.
Continue-reading overlay button (`showContinueReadingButtonProvider`) opens the
first unread chapter directly.

## Grouping

`libraryGroupTypeProvider` persists the selected mode:

| Constant | Value | Behaviour |
|---|---|---|
| `LibraryGroup.byDefault` | 0 | Category tabs (server-side categories, existing behaviour) |
| `LibraryGroup.bySource` | 1 | Client-side source tabs, sorted by name |
| `LibraryGroup.byStatus` | 2 | Client-side status tabs, sorted by `statusOrder` |
| `LibraryGroup.byTrackStatus` | 3 | Per-track-status tabs (shown only when trackers logged in) |
| `LibraryGroup.ungrouped` | 4 | Single "All" tab |

`kDefaultLibraryGroupType = 0` — typed constant replacing raw `DBKeys.*.initial as int`
casts at all three call sites.

`groupLibrary()` is a pure function; tested in `test/library/library_grouping_test.dart`.

## Organizer tabs

The organizer sheet (`LibraryMangaOrganizer`) has four tabs:

- **Filter** — tri-state filters (unread, downloaded, completed, started, bookmarked,
  on-device, lewd); minimum-rating row; category include/exclude dialog; tag
  include/exclude dialog (options from `libraryTagListProvider`); per-tracker tri-state
  rows. Single logged-in tracker collapses heading + row into one "Tracked" toggle tile
  (Komikku LibrarySettingsDialog.kt:190-215 parity).
- **Sort** — `MangaSort` radio + direction toggle.
- **Display** — display mode radio; portrait/landscape column count sliders;
  badge toggles (downloaded, unread, continue-reading, language, local, source);
  tab-section toggles (category tabs, show hidden, item count).
- **Group** — grouping mode radio (BY_TRACK_STATUS shown only when trackers present).

## Persistence (DBKeys)

`mangaSort` (**`MangaSort.lastRead`**), `mangaSortDirection` (`true`/asc),
`mangaFilter{Downloaded,Unread,Completed,Started,Bookmarked,Offline,Lewd}` (`null`),
per-tracker filter map, category include/exclude lists, tag include/exclude lists
(`filterTags`/`filterTagsInclude`/`filterTagsExclude`), `mangaFilterMinRating` (0),
`libraryDisplayMode` (`grid`), `libraryPortraitColumns` (0 = auto),
`libraryLandscapeColumns` (0 = auto), `downloadedBadge` (`false`),
`unreadBadge` (`true`), `languageBadge` (`false`), `useLangIcon` (`false`),
`localBadge` (`false`), `sourceBadge` (`false`),
`showContinueReadingButton` (`false`), `categoryTabs` (`true`),
`showHiddenCategories` (`false`), `categoryNumberOfItems` (`false`),
`libraryGroupType` (0 = BY_DEFAULT), `gridMangaCoverWidth` (192.0).
Search query is session-only (no persistence).

## Gotchas

- **`lastRead` sort is internally reversed** — the comparator swaps m1/m2 arguments.
  "Ascending" direction yields **most-recently-read first**. Do not fix — Mihon parity,
  and the **default sort is `lastRead`**, so new installs open most-recent-first.
- **Empty categories are hidden** (`visibleCategoryListProvider`) — a new empty
  category is invisible in the tab bar until it has manga. The edit screen shows all.
- **Filter/sort/display/group changes are global** — applied to all tabs at once.
- **Tab index** (BY_DEFAULT mode) comes from the `:categoryId` route param matched
  to the visible category list — not persisted as a tab index.
- **Badge providers live outside the library tree** (`widgets/manga_cover/providers/`),
  shared with browse.
- **Timestamps are string-encoded epochs** parsed inline — invalid/missing values
  sort to the bottom.
- **BY_TRACK_STATUS** tab is only offered in the Group tab when at least one tracker
  is logged in (`loggedInTrackersProvider`).
- **Random sort seed** is session-stable: resets on app restart, not on every toggle.
