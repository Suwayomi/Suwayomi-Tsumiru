# Browse: Sources & Extensions

## Purpose

The "Browse" tab: discovering/installing extensions, listing sources, browsing a single source (popular/latest/search with filters), and global search across all sources.

## Structure

`browse_screen.dart` is a two-tab shell (Sources / Extensions) with a shared AppBar. Sources-tab search pushes `GlobalSearchRoute`; Extensions-tab search filters in place via `extensionQueryProvider`.

| Area | Key files |
|---|---|
| Extensions | `presentation/extension/{extension_screen, controller/extension_controller}.dart`, `widgets/extension_list_tile.dart`, `data/extension_repository/extension_repository.dart` |
| Sources | `presentation/source/{source_screen, controller/source_controller}.dart`, `widgets/source_list_tile.dart`, `data/source_repository/source_repository.dart` |
| Source manga list | `presentation/source_manga_list/{source_manga_list_screen, controller/...}.dart`, `widgets/{source_manga_grid_view, source_manga_list_view, source_manga_filter, filter_to_widget}.dart` |
| Global search | `presentation/global_search/{global_search_screen, controller/source_quick_search_controller}.dart`, `widgets/source_short_search.dart` |
| Source preferences | `presentation/source_preference/...` |

## Domain types

All `typedef`s over GraphQL codegen (except `Language`, which is `freezed`): `Extension = Fragment$ExtensionDto`, `SourceDto = Fragment$SourceDto`, `SourceType = Enum$FetchSourceMangaType` (POPULAR/LATEST/SEARCH/$unknown), `MangaPage = Fragment$SourceMangaPage`. Filters: `Filter`/`PrimitiveFilter` union + 7 concrete subtypes; `SourcePreference` union + 5 types.

## Notable behavior

- **Extensions:** grouped into update/installed/by-language; NSFW-gated; language allowlist persisted (`DBKeys.extensionLanguageFilter`). Install via `UpdateExtension` or file upload (`InstallExternalExtension`).
- **Sources:** grouped lastUsed/all/by-language/localSource; tapping saves `sourceLastUsedProvider` and navigates to `SourceTypeRoute(POPULAR)`.
- **Source browsing:** `infinite_scroll_pagination` `PagingController<int, MangaDto>` (`firstPageKey: 1`); POPULAR/LATEST/SEARCH chips; filter drawer (end-drawer tablet / bottom-sheet phone) rendered via exhaustive `switch` in `filter_to_widget.dart`.
- **Global search:** `quickSearchResultsProvider(query)` fans out `sourceQuickSearchMangaListProvider(sourceId, query)` across filtered sources, all wrapped in `rateLimitQueueProvider(query)`.

## Gotchas

- **Extension list fetch is a mutation** (`FetchExtensionList`) — every "refresh" tells the server to re-check for updates (a roundtrip).
- **`SourceType.SEARCH` is labelled "Filter"** in the UI (`sourceTypeFilter`), matching Tachiyomi convention.
- **`sourceDisplayModeProvider` uses `DisplayMode.sourceDisplayList`** (grid/list subset); `descriptiveList` is lumped with `list`.
- **Filter leaf widgets use `kPositionPlaceholder`** — real position is assigned by the parent; don't set it in the leaf.
- **Global search rate-limits by query string** (a queue per distinct query), not by time.
- **`baseSourcePreferenceListProvider` uses `ref.read`** (not reactive) — invalidate to refresh.
- **Source language filter sorts enabled-first once** on dialog open (frozen for the session).
- **Local source `lang` is the literal `"localsourcelang"`** — explicitly removed and pinned to the bottom.
- **`MangaPageDto` fragment is dead code** (repo uses `SourceMangaPage`).
- **Installing an extension auto-adds its language** to the source language filter so the new source is visible.
