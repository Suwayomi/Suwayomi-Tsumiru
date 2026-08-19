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
// Grouping helpers
// ---------------------------------------------------------------------------

/// Groups consecutive chapters that share the same manga and the same calendar
/// day into [_GroupedEntry] records. Ungrouped chapters become a [_GroupedEntry]
/// with an empty [tail].
List<_GroupedEntry> _groupItems(List<ChapterWithMangaDto> items) {
  final result = <_GroupedEntry>[];
  for (final item in items) {
    final itemDate = int.tryParse(item.fetchedAt);
    final last = result.lastOrNull;
    if (last != null &&
        last.head.mangaId == item.mangaId &&
        itemDate.isSameDayAs(int.tryParse(last.head.fetchedAt))) {
      result[result.length - 1] = last.copyWithTail(item);
    } else {
      result.add(_GroupedEntry(head: item, tail: const []));
    }
  }
  return result;
}

/// Picks the representative chapter for a group: the last unread chapter,
/// or the first chapter if all are already read — matching WebUI behaviour.
ChapterWithMangaDto _pickHead(List<ChapterWithMangaDto> chapters) {
  assert(chapters.isNotEmpty);
  return chapters.lastWhere(
    (c) => !c.isRead,
    orElse: () => chapters.first,
  );
}

class _GroupedEntry {
  const _GroupedEntry({required this.head, required this.tail});

  final ChapterWithMangaDto head;
  final List<ChapterWithMangaDto> tail;

  _GroupedEntry copyWithTail(ChapterWithMangaDto extra) {
    final all = [head, ...tail, extra];
    final newHead = _pickHead(all);
    final newTail = [...all]..remove(newHead);
    return _GroupedEntry(head: newHead, tail: newTail);
  }
}

// ---------------------------------------------------------------------------
// Paged list widget
// ---------------------------------------------------------------------------

class _UpdatesPagedList extends StatelessWidget {
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

  Future<void> _updatePair(ChapterWithMangaDto item) async {
    final chapter = await refetchChapter(item.id);
    final list = [...?controller.itemList];
    final i = list.indexWhere((e) => e.id == item.id);
    if (i < 0) return;
    list[i] = list[i].copyWith(
      isRead: (chapter?.isRead ?? false) || list[i].isRead,
      isDownloaded: chapter?.isDownloaded,
      lastPageRead: chapter?.lastPageRead,
    );
    controller.itemList = list;
  }

  Future<void> _refreshManga(int mangaId) async {
    final startGeneration = getGeneration();
    final ids = [
      for (final row in [...?controller.itemList])
        if (row.mangaId == mangaId) row.id,
    ];
    final chapters = await fetchChaptersInBatches(
      ids: ids,
      fetch: refetchChapter,
    );
    if (!screenContext.mounted || getGeneration() != startGeneration) return;
    controller.itemList = patchRowsForManga(
      rows: [...?controller.itemList],
      mangaId: mangaId,
      chapters: chapters,
    );
  }

  void _toggleSelect(ChapterDto val) {
    if ((val.id).isNull) return;
    selectedChapters.value = selectedChapters.value.toggleKey(val.id, val);
  }

  Widget _buildItem(BuildContext context, ChapterWithMangaDto _, int flatIndex) {
    final items = controller.itemList ?? [];
    final isGrouped = groupingMode != UpdatesGroupingMode.disabled;

    // Build the display list up to and including flatIndex to determine which
    // group this flat index corresponds to, using a running fold.
    final groups = isGrouped ? _groupItems(items) : null;

    // Re-index: flatIndex is in the *original* flat list; find the group it
    // belongs to and the display index.
    if (groups != null) {
      // Each group occupies exactly one display slot.
      final displayIndex = _flatToDisplayIndex(items, groups, flatIndex);
      if (displayIndex == null) return const SizedBox.shrink();

      // Only render when flatIndex is the canonical "head" of the group to
      // avoid duplicate rendering. The head's flat index is where the
      // group's head item sits in the original list.
      final group = groups[displayIndex];
      if (items[flatIndex].id != group.head.id) return const SizedBox.shrink();

      final tile = _buildGroupTile(context, group);
      return _wrapWithDateHeader(context, items, flatIndex, tile);
    }

    // Ungrouped path — identical to the original flat behaviour.
    final item = items[flatIndex];
    final tile = ChapterMangaListTile(
      chapterWithMangaDto: item,
      updatePair: () => _updatePair(item),
      refreshManga: () => _refreshManga(item.mangaId),
      isSelected: selectedChapters.value.containsKey(item.id),
      canTapSelect: selectedChapters.value.isNotEmpty,
      toggleSelect: (val) => _toggleSelect(val),
    );
    return _wrapWithDateHeader(context, items, flatIndex, tile);
  }

  Widget _buildGroupTile(BuildContext context, _GroupedEntry group) {
    return ChapterMangaGroupedTile(
      head: group.head,
      tail: group.tail,
      updatePairFor: (chapter) => () => _updatePair(chapter),
      refreshManga: () => _refreshManga(group.head.mangaId),
      isSelected: selectedChapters.value.containsKey(group.head.id),
      canTapSelect: selectedChapters.value.isNotEmpty,
      toggleSelect: (val) => _toggleSelect(val),
    );
  }

  Widget _wrapWithDateHeader(
    BuildContext context,
    List<ChapterWithMangaDto> items,
    int flatIndex,
    Widget tile,
  ) {
    int? previousDate;
    try {
      previousDate = int.tryParse(items[flatIndex - 1].fetchedAt);
    } catch (_) {
      previousDate = null;
    }
    final currentDate = int.tryParse(items[flatIndex].fetchedAt);
    if (currentDate.isSameDayAs(previousDate)) return tile;
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

  /// Maps a flat list index to the display-group index, or null if this
  /// flat item is not the group head and should be hidden.
  int? _flatToDisplayIndex(
    List<ChapterWithMangaDto> items,
    List<_GroupedEntry> groups,
    int flatIndex,
  ) {
    int flatCursor = 0;
    for (int g = 0; g < groups.length; g++) {
      final group = groups[g];
      final groupSize = 1 + group.tail.length;
      if (flatIndex >= flatCursor && flatIndex < flatCursor + groupSize) {
        // Check if this flatIndex points to the head.
        if (items[flatIndex].id == group.head.id) return g;
        return null; // tail item — suppress rendering
      }
      flatCursor += groupSize;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return PagedSliverList(
      pagingController: controller,
      builderDelegate: PagedChildBuilderDelegate<ChapterWithMangaDto>(
        firstPageProgressIndicatorBuilder: (context) =>
            const CenterSorayomiShimmerIndicator(),
        firstPageErrorIndicatorBuilder: (context) => Emoticons(
          title: controller.error.toString(),
          button: TextButton(
            onPressed: resetList,
            child: Text(context.l10n.retry),
          ),
        ),
        noItemsFoundIndicatorBuilder: (context) => Emoticons(
          title: context.l10n.noUpdatesFound,
          button: TextButton(
            onPressed: resetList,
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
