// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';

import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/hooks/paging_controller_hook.dart';
import '../../../../widgets/custom_circular_progress_indicator.dart';
import '../../../../widgets/emoticons.dart';
import '../../data/updates/updates_repository.dart';
import '../../domain/chapter/chapter_model.dart';
import '../../domain/chapter/graphql/__generated__/fragment.graphql.dart';
import '../../widgets/chapter_actions/multi_chapters_actions_bottom_app_bar.dart';
import '../../widgets/update_status_fab.dart';
import '../../widgets/update_status_popup_menu.dart';
import '../reader/controller/reader_controller.dart';
import 'widgets/chapter_manga_list_tile.dart';

class UpdatesScreen extends HookConsumerWidget {
  const UpdatesScreen({super.key});

  Future<void> _fetchPage(
    UpdatesRepository repository,
    PagingController<int, ChapterWithMangaDto> controller,
    int pageKey,
  ) async {
    AsyncValue.guard(
      () => repository.getRecentChaptersPage(pageNo: pageKey),
    ).then(
      (value) => value.whenOrNull(
        data: (recentChaptersPage) {
          try {
            if (recentChaptersPage != null) {
              if (recentChaptersPage.pageInfo.hasNextPage) {
                controller
                    .appendPage([...recentChaptersPage.nodes], pageKey + 1);
              } else {
                controller.appendLastPage([...recentChaptersPage.nodes]);
              }
            }
          } catch (e) {
            //
          }
        },
        error: (error, stackTrace) => controller.error = error,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller =
        usePagingController<int, ChapterWithMangaDto>(firstPageKey: 0);
    final updatesRepository = ref.watch(updatesRepositoryProvider);
    final isUpdatesChecking = ref
        .watch(updatesSocketProvider
            .select((value) => value.value?.isRunning))
        .ifNull();
    final lastUpdated = ref.watch(libraryLastUpdatedProvider).value;
    final selectedChapters = useState<Map<int, ChapterDto>>({});
    useEffect(() {
      controller.addPageRequestListener((pageKey) => _fetchPage(
            updatesRepository,
            controller,
            pageKey,
          ));
      return;
    }, []);
    useEffect(() {
      if (!isUpdatesChecking) {
        try {
          selectedChapters.value = ({});
          controller.refresh();
        } catch (e) {
          //
        }
      }
      return null;
    }, [isUpdatesChecking]);
    return Scaffold(
      floatingActionButton:
          selectedChapters.value.isEmpty ? const UpdateStatusFab() : null,
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
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(context.l10n.updates),
                  if (lastUpdated != null &&
                      (int.tryParse(lastUpdated) ?? 0) > 0) ...[
                    const SizedBox(height: 5),
                    Text(
                      context.l10n.libraryLastUpdated(
                          int.parse(lastUpdated).toTimeAgo(context)),
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.theme.colorScheme.onSurfaceVariant,
                        height: 1.1,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
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
              afterOptionSelected: () async => controller.refresh(),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async {
          selectedChapters.value = ({});
          controller.refresh();
        },
        child: PagedListView(
          pagingController: controller,
          builderDelegate: PagedChildBuilderDelegate<ChapterWithMangaDto>(
            firstPageProgressIndicatorBuilder: (context) =>
                const CenterSorayomiShimmerIndicator(),
            firstPageErrorIndicatorBuilder: (context) => Emoticons(
              title: controller.error.toString(),
              button: TextButton(
                onPressed: () => controller.refresh(),
                child: Text(context.l10n.retry),
              ),
            ),
            noItemsFoundIndicatorBuilder: (context) => Emoticons(
              title: context.l10n.noUpdatesFound,
              button: TextButton(
                onPressed: () => controller.refresh(),
                child: Text(context.l10n.refresh),
              ),
            ),
            itemBuilder: (context, item, index) {
              int? previousDate;
              try {
                previousDate = int.tryParse(
                    controller.itemList?[index - 1].fetchedAt ?? "");
              } catch (e) {
                previousDate = null;
              }
              final chapterTile = ChapterMangaListTile(
                chapterWithMangaDto: item,
                updatePair: () async {
                  final chapter = await ref
                      .refresh(chapterProvider(chapterId: item.id).future);
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
                isSelected: selectedChapters.value.containsKey(item.id),
                canTapSelect: selectedChapters.value.isNotEmpty,
                toggleSelect: (ChapterDto val) {
                  if ((val.id).isNull) return;
                  selectedChapters.value =
                      (selectedChapters.value.toggleKey(val.id, val));
                },
              );
              if ((int.tryParse(item.fetchedAt)).isSameDayAs(previousDate)) {
                return chapterTile;
              } else {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      title: Text(
                        int.tryParse(item.fetchedAt)
                            .toDaysAgoFromSeconds(context),
                      ),
                    ),
                    chapterTile,
                  ],
                );
              }
            },
          ),
        ),
      ),
    );
  }
}
