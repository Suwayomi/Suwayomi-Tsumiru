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
import 'widgets/chapter_manga_list_tile.dart';
import 'widgets/updates_filter.dart';

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
            PagedSliverList(
              pagingController: controller,
              builderDelegate: PagedChildBuilderDelegate<ChapterWithMangaDto>(
                firstPageProgressIndicatorBuilder: (context) =>
                    const CenterSorayomiShimmerIndicator(),
                firstPageErrorIndicatorBuilder: (context) => Emoticons(
                  title: controller.error.toString(),
                  button: TextButton(
                    onPressed: () => resetList(),
                    child: Text(context.l10n.retry),
                  ),
                ),
                noItemsFoundIndicatorBuilder: (context) => Emoticons(
                  title: context.l10n.noUpdatesFound,
                  button: TextButton(
                    onPressed: () => resetList(),
                    child: Text(context.l10n.refresh),
                  ),
                ),
                itemBuilder: (context, item, index) {
                  int? previousDate;
                  try {
                    previousDate = int.tryParse(
                      controller.itemList?[index - 1].fetchedAt ?? "",
                    );
                  } catch (e) {
                    previousDate = null;
                  }
                  final chapterTile = ChapterMangaListTile(
                    chapterWithMangaDto: item,
                    updatePair: () async {
                      final chapter = await refetchChapter(ref, item.id);
                      // Locate the row by id, not the captured build-time index —
                      // the list may have changed (paging/refresh) while the reader
                      // was open, so an index-based patch could hit the wrong row.
                      final list = [...?controller.itemList];
                      final i = list.indexWhere((e) => e.id == item.id);
                      if (i < 0) return;
                      list[i] = list[i].copyWith(
                        // Upgrade-only: reading never un-reads, so a stale/slow
                        // refetch that still reports unread must not flip an
                        // already-read row back. Only ever grey it out.
                        isRead: (chapter?.isRead ?? false) || list[i].isRead,
                        isDownloaded: chapter?.isDownloaded,
                        lastPageRead: chapter?.lastPageRead,
                      );
                      controller.itemList = list;
                    },
                    refreshManga: () async {
                      final mangaId = item.mangaId;
                      final startGeneration = generation.value;
                      final ids = [
                        for (final row in [...?controller.itemList])
                          if (row.mangaId == mangaId) row.id,
                      ];
                      // Per chapter rather than via mangaChapterList: refreshing
                      // that one also runs the offline reconcile, and merely
                      // coming back to this list must never delete a download.
                      final chapters = await fetchChaptersInBatches(
                        ids: ids,
                        fetch: (id) => refetchChapter(ref, id),
                      );
                      // Same staleness rule as _fetchPage: a refresh or filter
                      // change during the fetch leaves these rows describing a
                      // list that no longer exists.
                      if (!screenContext.mounted ||
                          generation.value != startGeneration) {
                        return;
                      }
                      controller.itemList = patchRowsForManga(
                        rows: [...?controller.itemList],
                        mangaId: mangaId,
                        chapters: chapters,
                      );
                    },
                    isSelected: selectedChapters.value.containsKey(item.id),
                    canTapSelect: selectedChapters.value.isNotEmpty,
                    toggleSelect: (ChapterDto val) {
                      if ((val.id).isNull) return;
                      selectedChapters.value = (selectedChapters.value
                          .toggleKey(val.id, val));
                    },
                  );
                  if ((int.tryParse(
                    item.fetchedAt,
                  )).isSameDayAs(previousDate)) {
                    return chapterTile;
                  } else {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          title: Text(
                            int.tryParse(
                              item.fetchedAt,
                            ).toDaysAgoFromSeconds(context),
                          ),
                        ),
                        chapterTile,
                      ],
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
