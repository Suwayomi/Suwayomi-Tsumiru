// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';

import '../../../../constants/app_sizes.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/hooks/paging_controller_hook.dart';
import '../../../../widgets/custom_circular_progress_indicator.dart';
import '../../../../widgets/emoticons.dart';
import '../../../settings/presentation/syncyomi/syncyomi_sync.dart';
import '../../data/updates/updates_repository.dart';
import '../../domain/chapter/chapter_model.dart';
import '../../domain/chapter/graphql/__generated__/fragment.graphql.dart';
import '../../domain/updates/updates_grouping.dart';
import '../../domain/updates/updates_row_patch.dart';
import '../../widgets/chapter_actions/multi_chapters_actions_bottom_app_bar.dart';
import '../../widgets/update_status_fab.dart';
import '../../widgets/update_status_popup_menu.dart';
import '../reader/controller/reader_controller.dart';
import 'controller/updates_filter_controller.dart';
import 'controller/updates_grouping_controller.dart';
import 'widgets/chapter_manga_grouped_tile.dart';
import 'widgets/chapter_manga_list_tile.dart';
import 'widgets/updates_filter.dart';

// ---------------------------------------------------------------------------
// Paged list widget
// ---------------------------------------------------------------------------

class _UpdatesPagedList extends StatefulWidget {
  const _UpdatesPagedList({
    required this.controller,
    required this.groupingMode,
    required this.selectedChapters,
    required this.getGeneration,
    required this.screenContext,
    required this.resetList,
    required this.refetchChapter,
  });

  final ServerPagingController<ChapterWithMangaDto> controller;
  final UpdatesGroupingMode groupingMode;
  final ValueNotifier<Map<int, ChapterDto>> selectedChapters;
  final ValueGetter<int> getGeneration;
  final BuildContext screenContext;
  final VoidCallback resetList;
  final Future<ChapterDto?> Function(int chapterId) refetchChapter;

  @override
  State<_UpdatesPagedList> createState() => _UpdatesPagedListState();
}

class _UpdatesPagedListState extends State<_UpdatesPagedList> {
  // Memoizes the grouping pass per loaded-pages instance instead of
  // recomputing it once per visible row: PagedSliverList's itemBuilder calls
  // _buildItem separately for every rendered row, and grouping/index-mapping
  // re-walk the WHOLE loaded (all-pages-so-far) list each time they're asked.
  // This State persists across those calls (only scrolling triggers them, not
  // a rebuild of this widget), so caching on the pages list's identity is
  // enough to turn an O(rows x loaded-items) pass back into one
  // O(loaded-items) pass reused by every row. The key is `pages`, not
  // `items`: `items` flattens into a fresh list on every read. Requires State
  // (not StatelessWidget) since Widget subclasses are @immutable — plain
  // mutable fields on the widget itself would fail analysis (must_be_immutable
  // / const_constructor_with_non_final_field).
  List<List<ChapterWithMangaDto>>? _memoPages;
  List<ChapterWithMangaDto>? _memoItems;
  List<UpdatesGroupedEntry>? _memoGroups;
  Map<int, int>? _memoHeadIndex;
  Set<int>? _memoHeaderIndices;

  ({
    List<ChapterWithMangaDto> items,
    List<UpdatesGroupedEntry> groups,
    Map<int, int> headIndex,
    Set<int> headerIndices,
  }) _groupingFor(
    List<List<ChapterWithMangaDto>>? pages,
  ) {
    if (_memoPages != null && identical(_memoPages, pages)) {
      return (
        items: _memoItems!,
        groups: _memoGroups!,
        headIndex: _memoHeadIndex!,
        headerIndices: _memoHeaderIndices!,
      );
    }
    final items = [
      for (final page in pages ?? <List<ChapterWithMangaDto>>[]) ...page,
    ];
    final groups = groupUpdatesForDisplay(items);
    final headIndex = headFlatIndexToDisplayIndex(groups);
    final headerIndices = dateHeaderIndices(items);
    _memoPages = pages;
    _memoItems = items;
    _memoGroups = groups;
    _memoHeadIndex = headIndex;
    _memoHeaderIndices = headerIndices;
    return (
      items: items,
      groups: groups,
      headIndex: headIndex,
      headerIndices: headerIndices,
    );
  }

  Future<void> _updatePair(ChapterWithMangaDto item) async {
    final chapter = await widget.refetchChapter(item.id);
    if (!widget.screenContext.mounted) return;
    widget.controller.mapItems(
      (row) => row.id != item.id
          ? row
          : row.copyWith(
              isRead: (chapter?.isRead ?? false) || row.isRead,
              isDownloaded: chapter?.isDownloaded,
              lastPageRead: chapter?.lastPageRead,
            ),
    );
  }

  Future<void> _refreshManga(int mangaId) async {
    final startGeneration = widget.getGeneration();
    final ids = [
      for (final row in widget.controller.items ?? <ChapterWithMangaDto>[])
        if (row.mangaId == mangaId) row.id,
    ];
    final chapters = await fetchChaptersInBatches(
      ids: ids,
      fetch: widget.refetchChapter,
    );
    if (!widget.screenContext.mounted ||
        widget.getGeneration() != startGeneration) {
      return;
    }
    final controller = widget.controller;
    controller.value = controller.value.copyWith(
      pages: [
        for (final page in controller.pages ?? <List<ChapterWithMangaDto>>[])
          patchRowsForManga(rows: page, mangaId: mangaId, chapters: chapters),
      ],
    );
  }

  void _toggleSelect(ChapterDto val) {
    if ((val.id).isNull) return;
    widget.selectedChapters.value =
        widget.selectedChapters.value.toggleKey(val.id, val);
  }

  Widget _buildItem(
    BuildContext context,
    PagingState<int, ChapterWithMangaDto> state,
    int flatIndex,
  ) {
    final isGrouped = widget.groupingMode != UpdatesGroupingMode.disabled;
    // Memoized per pages instance — see _groupingFor's doc comment. Needed on
    // both paths below since date headers are independent of manga grouping.
    final grouping = _groupingFor(state.pages);
    final items = grouping.items;

    if (isGrouped) {
      // A flat index missing from headIndex is a tail member (or the head of
      // a DIFFERENT group already rendered): suppress it either way.
      final displayIndex = grouping.headIndex[flatIndex];
      if (displayIndex == null) return const SizedBox.shrink();

      final group = grouping.groups[displayIndex];
      final tile = _buildGroupTile(context, group);
      return _wrapWithDateHeader(
        context,
        items,
        flatIndex,
        tile,
        grouping.headerIndices,
      );
    }

    // Ungrouped path — identical to the original flat behaviour.
    final item = items[flatIndex];
    final tile = ChapterMangaListTile(
      chapterWithMangaDto: item,
      updatePair: () => _updatePair(item),
      refreshManga: () => _refreshManga(item.mangaId),
      isSelected: widget.selectedChapters.value.containsKey(item.id),
      canTapSelect: widget.selectedChapters.value.isNotEmpty,
      toggleSelect: (val) => _toggleSelect(val),
    );
    return _wrapWithDateHeader(
      context,
      items,
      flatIndex,
      tile,
      grouping.headerIndices,
    );
  }

  Widget _buildGroupTile(BuildContext context, UpdatesGroupedEntry group) {
    return ChapterMangaGroupedTile(
      head: group.head,
      tail: group.tail,
      updatePairFor: (chapter) => () => _updatePair(chapter),
      refreshManga: () => _refreshManga(group.head.mangaId),
      isSelectedFor: (chapter) =>
          widget.selectedChapters.value.containsKey(chapter.id),
      canTapSelect: widget.selectedChapters.value.isNotEmpty,
      toggleSelect: (val) => _toggleSelect(val),
    );
  }

  Widget _wrapWithDateHeader(
    BuildContext context,
    List<ChapterWithMangaDto> items,
    int flatIndex,
    Widget tile,
    Set<int> headerIndices,
  ) {
    if (!headerIndices.contains(flatIndex)) return tile;
    final currentDate = int.tryParse(items[flatIndex].fetchedAt);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          title: Text(currentDate.toDaysAgoFromSeconds(context)),
        ),
        tile,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PagingListener(
      controller: widget.controller,
      builder: (context, state, fetchNextPage) => PagedSliverList(
        state: state,
        fetchNextPage: fetchNextPage,
        builderDelegate: PagedChildBuilderDelegate<ChapterWithMangaDto>(
          firstPageProgressIndicatorBuilder: (context) =>
              const CenterSorayomiShimmerIndicator(),
          firstPageErrorIndicatorBuilder: (context) => Emoticons(
            title: state.error.toString(),
            button: TextButton(
              onPressed: widget.resetList,
              child: Text(context.l10n.retry),
            ),
          ),
          noItemsFoundIndicatorBuilder: (context) => Emoticons(
            title: context.l10n.noUpdatesFound,
            button: TextButton(
              onPressed: widget.resetList,
              child: Text(context.l10n.refresh),
            ),
          ),
          itemBuilder: (context, _, index) => _buildItem(context, state, index),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Refetches one chapter, holding its autoDispose provider open so a bare
/// refresh with nothing listening can't tear it down mid-fetch and throw.
Future<ChapterDto?> refetchChapter(WidgetRef ref, int chapterId) async {
  final provider = chapterProvider(chapterId: chapterId);
  final keepAlive = ref.listenManual(provider, (_, _) {});
  try {
    return await ref.refresh(provider.future);
  } finally {
    keepAlive.close();
  }
}

/// Extracts new items from a single fetched page when live-patching the
/// Updates list after a background library check.
///
/// Returns all items from [nodes] that are not in [existingIds], stopping
/// before the first known ID. [boundaryFound] is true when a known ID was
/// encountered, meaning the caller has collected all new items up to the
/// existing list and can stop fetching further pages.
({List<ChapterWithMangaDto> items, bool boundaryFound})
    extractNewUpdatesFromPage(
  List<ChapterWithMangaDto> nodes,
  Set<int> existingIds,
) {
  final knownIndex = nodes.indexWhere((c) => existingIds.contains(c.id));
  if (knownIndex >= 0) {
    return (items: nodes.take(knownIndex).toList(), boundaryFound: true);
  }
  return (items: nodes.toList(), boundaryFound: false);
}

class UpdatesScreen extends HookConsumerWidget {
  const UpdatesScreen({super.key});

  // A refresh or filter change while a request is in flight leaves it
  // describing a list that no longer exists; the controller drops its reply
  // rather than interleave two result sets.
  Future<ServerPage<ChapterWithMangaDto>> _fetchPage(
    UpdatesRepository repository,
    int pageKey,
    UpdatesFilter filter,
  ) async {
    final page =
        await repository.getRecentChaptersPage(pageNo: pageKey, filter: filter);
    if (page == null) return (items: <ChapterWithMangaDto>[], hasNextPage: false);
    return (items: [...page.nodes], hasNextPage: page.pageInfo.hasNextPage);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The item builder's context belongs to a row that recycles on scroll, so
    // post-await guards ask this one whether the screen itself is still alive.
    final screenContext = context;
    final updatesRepository = ref.watch(updatesRepositoryProvider);
    final lastUpdated = ref.watch(libraryLastUpdatedProvider).value;
    final selectedChapters = useState<Map<int, ChapterDto>>({});
    final filter = ref.watch(updatesFilterProvider);
    final hasActiveFilters = ref.watch(updatesHasActiveFiltersProvider);
    final groupingMode = ref.watch(updatesGroupingModeProvider) ??
        UpdatesGroupingMode.disabled;
    // The page fetcher is captured once, so it can't close over `filter` — it
    // reads the latest value through this holder instead.
    final latestFilter = useRef(filter);
    latestFilter.value = filter;
    final controller = useServerPagingController<ChapterWithMangaDto>(
      firstPageKey: 0,
      // Read per request: a LAN/remote endpoint switch replaces the client,
      // and the one captured on the first build is disposed with it.
      fetchPage: (pageKey) => _fetchPage(
        ref.read(updatesRepositoryProvider),
        pageKey,
        latestFilter.value,
      ),
    );
    // Bumped by every reset of the list, so replies from the previous one can be
    // recognised as stale and dropped.
    final generation = useRef(0);
    final resetList = useCallback(() {
      generation.value++;
      selectedChapters.value = ({});
      controller.refresh();
    }, []);
    // Use the lightweight running-only socket (not updatesSocketProvider, the
    // heavy feed that goes silent mid-run on large updates and can miss the
    // true→false edge). Pattern mirrors LibraryScreen's own update listener.
    //
    // On the true→false edge, fetch page 0 and prepend only the items that
    // aren't already in the list, so the user keeps their scroll position.
    // Falls back to doing nothing on error (pull-to-refresh still works).
    final lastRunningUpdates = useRef<bool>(false);
    Future<void> liveUpdate() async {
      final gen = generation.value;
      final existingIds = {
        for (final item in controller.items ?? <ChapterWithMangaDto>[])
          item.id,
      };
      final newItems = <ChapterWithMangaDto>[];
      // Walk pages until we hit a known ID (the boundary) or run out of pages.
      // Cap at 3 pages: beyond that the list is so stale that a full reset is
      // cleaner than prepending dozens of out-of-context entries.
      const maxPages = 3;
      for (var pageNo = 0; pageNo < maxPages; pageNo++) {
        final snapshot = await AsyncValue.guard(
          () => updatesRepository.getRecentChaptersPage(
            pageNo: pageNo,
            filter: latestFilter.value,
          ),
        );
        if (generation.value != gen) return;
        final page = snapshot.asData?.value;
        if (page == null) return;
        final result = extractNewUpdatesFromPage(page.nodes, existingIds);
        newItems.addAll(result.items);
        if (result.boundaryFound) break;
        if (!page.pageInfo.hasNextPage) break;
        if (pageNo == maxPages - 1) {
          resetList();
          return;
        }
      }
      if (newItems.isEmpty || !screenContext.mounted) return;
      // Prepended onto the first page so the keys, and the next page to
      // fetch, stay as they were.
      final pages = controller.pages;
      if (pages == null || pages.isEmpty) return;
      controller.value = controller.value.copyWith(
        pages: [
          [...newItems, ...pages.first],
          ...pages.skip(1),
        ],
      );
    }

    ref.listen(updateRunningSocketProvider, (_, next) {
      final running = next.value;
      if (running == null) return;
      if (lastRunningUpdates.value && !running) {
        liveUpdate();
      }
      lastRunningUpdates.value = running;
    });
    // Filtering happens server-side, so a changed filter invalidates every page
    // already loaded. Skip the mount run or page 0 would be fetched twice.
    final isFilterMount = useRef(true);
    useEffect(() {
      if (isFilterMount.value) {
        isFilterMount.value = false;
        return null;
      }
      resetList();
      return null;
    }, [filter]);
    return Scaffold(
      floatingActionButton: selectedChapters.value.isEmpty
          ? const UpdateStatusFab()
          : null,
      appBar: selectedChapters.value.isNotEmpty
          ? AppBar(
              leading: IconButton(
                onPressed: () => selectedChapters.value = ({}),
                icon: const Icon(Icons.close_rounded),
              ),
              title: Text(
                context.l10n.numSelected(selectedChapters.value.length),
              ),
            )
          : AppBar(
              // Single-line, like every other tab. Stacking the last-updated
              // line in here made this the only header whose title sat at a
              // different height; it lives at the top of the list instead,
              // which is where Mihon keeps it.
              title: Text(context.l10n.updates),
              actions: [
                SyncYomiSyncButton(onSynced: resetList),
                IconButton(
                  icon: const Icon(Icons.filter_list_rounded),
                  tooltip: context.l10n.filter,
                  // Tinted while filtered, so a short list reads as "filtered"
                  // rather than "nothing new". Komikku uses amber here; ours
                  // comes from the theme.
                  color: hasActiveFilters
                      ? context.theme.colorScheme.primary
                      : null,
                  onPressed: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    shape: RoundedRectangleBorder(
                      borderRadius: KBorderRadius.rT16.radius,
                    ),
                    clipBehavior: Clip.hardEdge,
                    builder: (_) => const UpdatesFilterSheet(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.calendar_month_rounded),
                  tooltip: context.l10n.upcoming,
                  onPressed: () => const UpcomingRoute().push(context),
                ),
                const UpdateStatusPopupMenu(),
              ],
            ),
      bottomSheet: selectedChapters.value.isNotEmpty
          ? MultiChaptersActionsBottomAppBar(
              selectedChapters: selectedChapters,
              afterOptionSelected: () async => resetList(),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async => resetList(),
        child: CustomScrollView(
          slivers: [
            if (lastUpdated != null && (int.tryParse(lastUpdated) ?? 0) > 0)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Text(
                    context.l10n.libraryLastUpdated(
                      int.parse(lastUpdated).toTimeAgo(context),
                    ),
                    style: context.textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: context.theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            _UpdatesPagedList(
              controller: controller,
              groupingMode: groupingMode,
              selectedChapters: selectedChapters,
              getGeneration: () => generation.value,
              screenContext: screenContext,
              resetList: resetList,
              refetchChapter: (id) => refetchChapter(ref, id),
            ),
          ],
        ),
      ),
    );
  }
}
