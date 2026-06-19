# Library

## Purpose

Displays saved manga organized into server-side categories, with client-side sort, filter, search, and three display modes. All view state persists to SharedPreferences.

## Key files

| Path | Responsibility |
|---|---|
| `features/library/data/category_repository.dart` | Fetch categories + per-category manga; category CRUD/reorder |
| `features/library/data/graphql/query.graphql` | `AllCategories`, `GetCategoryMangas` + category mutations |
| `features/library/presentation/library/controller/library_controller.dart` | All library providers: fetch, filter, sort, display mode, query |
| `.../library/library_screen.dart` | Tab bar per category, AppBar search + filter, tablet end-drawer |
| `.../library/category_manga_list.dart` | Per-tab grid/list/descriptive-list |
| `.../library/widgets/library_manga_{organizer,filter,sort_tile,display}.dart` | Filter/Sort/Display tabs |
| `.../category/...` | Edit-category screen, tiles, dialogs, create FAB |
| `lib/src/widgets/manga_cover/providers/manga_cover_providers.dart` | `DownloadedBadge` / `UnreadBadge` (shared with browse) |

## Data flow

1. `categoryControllerProvider` → `AllCategories` (ordered `ORDER ASC`).
2. `nonZeroCategoryListProvider` keeps only categories with `mangas.totalCount > 0` (the tab bar source).
3. Each tab → `CategoryMangaList(categoryId)` → `categoryMangaListProvider(categoryId)` (`GetCategoryMangas`).
4. `categoryMangaListWithQueryAndFilterProvider(categoryId)` watches the raw list + all filter/sort/query providers, applies `applyMangaFilter` then `applyMangaSort` inline.

**`applyMangaFilter`** — five tri-state `bool?` filters ANDed (`null`=off, `true`/`false` via XOR): unread (`unreadCount>0`), downloaded (`downloadCount>0`), completed (`status=="COMPLETED"`), started (`lastReadChapter!=null`), bookmarked (`bookmarkCount>0`); text query last.

**`applyMangaSort`** — `MangaSort` × direction (`sortDirToggle` = `1` asc / `-1` desc): `alphabetical`, `unread`, `dateAdded` (`inLibraryAt`), `lastUpdated` (`latestFetchedChapter.fetchedAt`), `lastChapterDate` (`latestUploadedChapter.uploadDate`), `totalChapters`, `lastRead` (`lastReadChapter.lastReadAt`).

## Display, badges, grid

- `DisplayMode`: `grid` (`MangaCoverGridTile`), `list` (itemExtent 96), `descriptiveList` (itemExtent 176). Default `grid`.
- Badges: `downloadedBadge` (default **false**), `unreadBadge` (default **true**) — shared providers in `manga_cover/providers/`, controlled in the Display tab.
- Grid: `mangaCoverGridDelegate(size)` = `SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: gridMangaCoverWidth (192), childAspectRatio: 0.75, spacing 2.0)` — column count varies with width.

## Persistence (DBKeys)

`mangaSort` (**`MangaSort.lastRead`**), `mangaSortDirection` (`true`/asc), `mangaFilter{Downloaded,Unread,Completed,Started,Bookmarked}` (`null`), `libraryDisplayMode` (`grid`), `downloadedBadge` (`false`), `unreadBadge` (`true`), `gridMangaCoverWidth` (`192.0`). Search query is session-only (no persistence).

## Gotchas

- **`lastRead` sort is internally reversed** — the comparator is `m2.lastReadAt.compareTo(m1.lastReadAt)` (args swapped). So the "ascending" direction (`sortDirToggle = 1`) actually yields **most-recently-read first**. Every other sort key is normal. Do not "fix" this — it's intentional Mihon-parity, and the **default sort is `lastRead`**, so new installs open most-recent-first.
- **Empty categories are hidden** (`nonZeroCategoryListProvider`) — a new empty category is invisible in the tab bar until it has a manga. The edit screen shows all.
- **Filter/sort/display changes are global**, applied to all tabs at once — no per-category state.
- **`LibraryDisplayCategory` provider is vestigial** (declared, never set).
- **Tab index** comes from the `:categoryId` route param clamped to range — not persisted.
- **Badge providers live outside the library tree** (`widgets/manga_cover/providers/`), shared with browse. A `LanguageBadge` is fully commented out.
- **Timestamps are string-encoded epochs** parsed inline (`int.tryParse(... ?? '0') ?? 0`) — invalid/missing sort to the bottom.
