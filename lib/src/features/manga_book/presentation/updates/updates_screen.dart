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

  final PagingController<int, ChapterWithMangaDto> controller;
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
  // Memoizes the grouping pass per itemList instance instead of recomputing
  // it once per visible row: PagedSliverList's itemBuilder calls _buildItem
  // separately for every rendered row, and grouping/index-mapping re-walk
  // the WHOLE loaded (all-pages-so-far) list each time they're asked. This
  // State persists across those calls (only scrolling triggers them, not a
  // rebuild of this widget), so caching on the itemList's identity is enough
  // to turn an O(rows x loaded-items) pass back into one O(loaded-items) pass
  // reused by every row. Requires State (not StatelessWidget) since Widget
  // subclasses are @immutable — plain mutable fields on the widget itself
  // would fail analysis (must_be_immutable / const_constructor_with_non_final_field).
  List<ChapterWithMangaDto>? _memoItems;
  List<UpdatesGroupedEntry>? _memoGroups;
  Map<int, int>? _memoHeadIndex;
  Set<int>? _memoHeaderIndices;

  ({
    List<UpdatesGroupedEntry> groups,
    Map<int, int> headIndex,
    Set<int> headerIndices,
  }) _groupingFor(
    List<ChapterWithMangaDto> items,
  ) {
    if (identical(_memoItems, items)) {
      return (
        groups: _memoGroups!,
        headIndex: _memoHeadIndex!,
        headerIndices: _memoHeaderIndices!,
      );
    }
    final groups = groupUpdatesForDisplay(items);
    final headIndex = headFlatIndexToDisplayIndex(groups);
    final headerIndices = dateHeaderIndices(items);
    _memoItems = items;
    _memoGroups = groups;
    _memoHeadIndex = headIndex;
    _memoHeaderIndices = headerIndices;
    return (groups: groups, headIndex: headIndex, headerIndices: headerIndices);
  }

  Future<void> _updatePair(ChapterWithMangaDto item) async {
    final chapter = await widget.refetchChapter(item.id);
    final list = [...?widget.controller.itemList];
    final i = list.indexWhere((e) => e.id == item.id);
    if (i < 0) return;
    list[i] = list[i].copyWith(
      isRead: (chapter?.isRead ?? false) || list[i].isRead,
      isDownloaded: chapter?.isDownloaded,
      lastPageRead: chapter?.lastPageRead,
    );
    widget.controller.itemList = list;
  }

  Future<void> _refreshManga(int mangaId) async {
    final startGeneration = widget.getGeneration();
    final ids = [
      for (final row in [...?widget.controller.itemList])
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
    widget.controller.itemList = patchRowsForManga(
      rows: [...?widget.controller.itemList],
      mangaId: mangaId,
      chapters: chapters,
    );
  }

  void _toggleSelect(ChapterDto val) {
    if ((val.id).isNull) return;
    widget.selectedChapters.value =
        widget.selectedChapters.value.toggleKey(val.id, val);
  }

  Widget _buildItem(BuildContext context, ChapterWithMangaDto _, int flatIndex) {
    final items = widget.controller.itemList ?? [];
    final isGrouped = widget.groupingMode != UpdatesGroupingMode.disabled;
    // Memoized per itemList instance — see _groupingFor's doc comment. Needed
    // on both paths below since date headers are independent of manga
    // grouping.
    final grouping = _groupingFor(items);

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
    return PagedSliverList(
      pagingController: widget.controller,
      builderDelegate: PagedChildBuilderDelegate<ChapterWithMangaDto>(
        firstPageProgressIndicatorBuilder: (context) =>
            const CenterSorayomiShimmerIndicator(),
        firstPageErrorIndicatorBuilder: (context) => Emoticons(
          title: widget.controller.error.toString(),
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
        itemBuilder: _buildItem,
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

class UpdatesScreen extends HookConsumerWidget {
  const UpdatesScreen({super.key});

  Future<void> _fetchPage(
    UpdatesRepository repository,
    PagingController<int, ChapterWithMangaDto> controller,
    int pageKey,
    UpdatesFilter filter,
    int generation,
    ValueGetter<int> currentGeneration,
  ) async {
    AsyncValue.guard(
      () => repository.getRecentChaptersPage(pageNo: pageKey, filter: filter),
    ).then(
      (value) => value.whenOrNull(
        data: (recentChaptersPage) {
          // A refresh or filter change while this request was in flight leaves
          // it describing a list that no longer exists; appending its rows would
          // interleave two different result sets and skew the next page key.
          if (generation != currentGeneration()) return;
          try {
            if (recentChaptersPage != null) {
              if (recentChaptersPage.pageInfo.hasNextPage) {
                controller.appendPage([
                  ...recentChaptersPage.nodes,
                ], pageKey + 1);
              } else {
                controller.appendLastPage([...recentChaptersPage.nodes]);
              }
            }
          } catch (e) {
            //
          }
        },
        error: (error, stackTrace) {
          if (generation != currentGeneration()) return;
          controller.error = error;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = usePagingController<int, ChapterWithMangaDto>(
      firstPageKey: 0,
    );
    // The item builder's context belongs to a row that recycles on scroll, so
    // post-await guards ask this one whether the screen itself is still alive.
    final screenContext = context;
    final updatesRepository = ref.watch(updatesRepositoryProvider);
    final isUpdatesChecking = ref
        .watch(updatesSocketProvider.select((value) => value.value?.isRunning))
        .ifNull();
    final lastUpdated = ref.watch(libraryLastUpdatedProvider).value;
    final selectedChapters = useState<Map<int, ChapterDto>>({});
    final filter = ref.watch(updatesFilterProvider);
    final hasActiveFilters = ref.watch(updatesHasActiveFiltersProvider);
    final groupingMode = ref.watch(updatesGroupingModeProvider) ??
        UpdatesGroupingMode.disabled;
    // The page listener is registered once, so it can't close over `filter` —
    // it reads the latest value through this holder instead.
    final latestFilter = useRef(filter);
    latestFilter.value = filter;
    // Bumped by every reset of the list, so replies from the previous one can be
    // recognised as stale and dropped.
    final generation = useRef(0);
    final resetList = useCallback(() {
      generation.value++;
      selectedChapters.value = ({});
      controller.refresh();
    }, []);
    useEffect(() {
      controller.addPageRequestListener(
        (pageKey) => _fetchPage(
          updatesRepository,
          controller,
          pageKey,
          latestFilter.value,
          generation.value,
          () => generation.value,
        ),
      );
      return;
    }, []);
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
    useEffect(() {
      if (!isUpdatesChecking) {
        try {
          resetList();
        } catch (e) {
          //
        }
      }
      return null;
    }, [isUpdatesChecking]);
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
