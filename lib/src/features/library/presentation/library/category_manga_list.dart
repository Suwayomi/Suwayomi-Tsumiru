// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/app_sizes.dart';
import '../../../../constants/enum.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/emoticons.dart';
import '../../../../widgets/manga_cover/grid/manga_cover_grid_tile.dart';
import '../../../../widgets/manga_cover/list/manga_cover_descriptive_list_tile.dart';
import '../../../../widgets/manga_cover/list/manga_cover_list_tile.dart';
import '../../../../widgets/selection_action_bar.dart';
import '../../../manga_book/data/downloads/downloads_repository.dart';
import '../../../manga_book/data/manga_book/manga_book_repository.dart';
import '../../../manga_book/domain/chapter_batch/chapter_batch_model.dart';
import '../../../manga_book/domain/manga/manga_model.dart';
import '../../../manga_book/presentation/manga_details/widgets/edit_manga_category_dialog.dart';
import '../../../offline/data/offline_database.dart';
import '../../../offline/data/offline_download_providers.dart';
import '../../../offline/data/offline_repository.dart';
import '../../../settings/presentation/appearance/widgets/grid_cover_width_slider/grid_cover_width_slider.dart';
import 'controller/library_controller.dart';

class CategoryMangaList extends HookConsumerWidget {
  const CategoryMangaList({super.key, required this.categoryId});
  final int categoryId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider =
        categoryMangaListWithQueryAndFilterProvider(categoryId: categoryId);
    final mangaList = ref.watch(provider);
    final displayMode = ref.watch(libraryDisplayModeProvider);
    final gridWidth = ref.watch(gridMinWidthProvider);
    refresh() => ref.invalidate(categoryMangaListProvider(categoryId));
    useEffect(() {
      if (mangaList.isNotLoading) refresh();
      return;
    }, []);

    // Multi-select: long-press starts selection (Komikku-style), tap toggles
    // while selecting else opens the manga. Selection is per this category list.
    final selection = useState<Set<int>>(const {});
    final selecting = selection.value.isNotEmpty;
    void toggle(int id) {
      final next = {...selection.value};
      if (!next.add(id)) next.remove(id);
      selection.value = next;
    }

    void open(MangaDto manga) {
      if (selecting) {
        toggle(manga.id);
      } else {
        MangaRoute(mangaId: manga.id, categoryId: categoryId).push(context);
      }
    }

    // Mark every chapter of the selected series read / unread, via the bulk
    // chapter mutation (one batch per series).
    Future<void> markSelection(bool read) async {
      final ids = selection.value.toList();
      selection.value = const {};
      final repo = ref.read(mangaBookRepositoryProvider);
      for (final id in ids) {
        final chapters = await repo.getChapterList(id);
        final cids = <int>[for (final c in chapters ?? const []) c.id];
        if (cids.isNotEmpty) {
          await repo.modifyBulkChapters(
              ChapterBatch(ids: cids, patch: ChapterChange(isRead: read)));
        }
      }
      refresh();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(read
              ? 'Marked ${ids.length} series read'
              : 'Marked ${ids.length} series unread'),
        ));
      }
    }

    return mangaList.showUiWhenData(
      context,
      (data) {
        if (data.isBlank) {
          return Emoticons(
            title: context.l10n.noCategoryMangaFound,
            button: TextButton(
              onPressed: refresh,
              child: Text(context.l10n.refresh),
            ),
          );
        }
        final items = data!;
        final Widget grid = switch (displayMode) {
          DisplayMode.list || null => ListView.builder(
              itemExtent: 96,
              itemCount: items.length,
              itemBuilder: (context, index) => MangaCoverListTile(
                manga: items[index],
                selected: selection.value.contains(items[index].id),
                onPressed: () => open(items[index]),
                onLongPress: () => toggle(items[index].id),
                showCountBadges: true,
              ),
            ),
          DisplayMode.grid => GridView.builder(
              gridDelegate: mangaCoverGridDelegate(gridWidth),
              itemCount: items.length,
              itemBuilder: (context, index) => MangaCoverGridTile(
                manga: items[index],
                selected: selection.value.contains(items[index].id),
                onLongPress: () => toggle(items[index].id),
                onPressed: () => open(items[index]),
                showCountBadges: true,
                showDarkOverlay: false,
              ),
            ),
          DisplayMode.descriptiveList => ListView.builder(
              itemExtent: 176,
              itemCount: items.length,
              itemBuilder: (context, index) => MangaCoverDescriptiveListTile(
                manga: items[index],
                selected: selection.value.contains(items[index].id),
                onPressed: () => open(items[index]),
                onLongPress: () => toggle(items[index].id),
                showBadges: true,
              ),
            ),
        };

        final list = RefreshIndicator(
          onRefresh: () async => refresh(),
          child: grid,
        );

        // While selecting, swallow the system back to exit selection first, and
        // show a contextual action bar (Komikku-style) over the grid.
        return PopScope(
          canPop: !selecting,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) selection.value = const {};
          },
          child: Stack(
            children: [
              list,
              if (selecting)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _SelectionBar(
                    count: selection.value.length,
                    onSelectAll: () =>
                        selection.value = {for (final m in items) m.id},
                    onClear: () => selection.value = const {},
                    onMarkRead: () => markSelection(true),
                    onMarkUnread: () => markSelection(false),
                    onKeepOffline: () async {
                      final ids = selection.value.toList();
                      selection.value = const {};
                      final db = ref.read(offlineDatabaseProvider);
                      for (final id in ids) {
                        await db.setKeepRule(id, OfflineKeepRule.all, 3);
                        await reconcileMangaWidget(ref, id);
                      }
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Keeping ${ids.length} series offline'),
                        ));
                      }
                    },
                    onDownloadToServer: () async {
                      final ids = selection.value.toList();
                      selection.value = const {};
                      final repo = ref.read(mangaBookRepositoryProvider);
                      final dl = ref.read(downloadsRepositoryProvider);
                      for (final id in ids) {
                        final chapters = await repo.getChapterList(id);
                        final chapterIds = <int>[
                          for (final c in chapters ?? const []) c.id,
                        ];
                        if (chapterIds.isNotEmpty) {
                          await dl.addChaptersBatchToDownloadQueue(chapterIds);
                        }
                      }
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content:
                              Text('Downloading ${ids.length} series to server'),
                        ));
                      }
                    },
                    onEditCategories: () async {
                      // Single-manga category dialog when exactly one is picked;
                      // multi-manga category editing is a follow-up.
                      if (selection.value.length == 1) {
                        final id = selection.value.first;
                        final manga =
                            items.firstWhere((m) => m.id == id);
                        selection.value = const {};
                        await showDialog(
                          context: context,
                          builder: (context) => EditMangaCategoryDialog(
                            mangaId: id,
                            title: manga.title,
                          ),
                        );
                        refresh();
                      }
                    },
                  ),
                ),
            ],
          ),
        );
      },
      refresh: refresh,
    );
  }
}

/// Bottom action bar shown while library manga are multi-selected. Mirrors
/// Komikku's library selection menu, scoped to the actions we can wire to
/// existing APIs (sync offline / download to server). Mark-read and multi-manga
/// category edits are a follow-up.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.onSelectAll,
    required this.onClear,
    required this.onMarkRead,
    required this.onMarkUnread,
    required this.onKeepOffline,
    required this.onDownloadToServer,
    required this.onEditCategories,
  });

  final int count;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;
  final VoidCallback onMarkRead;
  final VoidCallback onMarkUnread;
  final VoidCallback onKeepOffline;
  final VoidCallback onDownloadToServer;
  final VoidCallback onEditCategories;

  @override
  Widget build(BuildContext context) {
    return SelectionActionBar(
      leading: [
        IconButton(
          tooltip: 'Clear',
          icon: const Icon(Icons.close_rounded),
          onPressed: onClear,
        ),
        Text('$count', style: context.textTheme.titleMedium),
      ],
      actions: [
        IconButton(
          tooltip: 'Select all',
          icon: const Icon(Icons.select_all_rounded),
          onPressed: onSelectAll,
        ),
        if (count == 1)
          IconButton(
            tooltip: 'Edit categories',
            icon: const Icon(Icons.label_outline_rounded),
            onPressed: onEditCategories,
          ),
        IconButton(
          tooltip: 'Mark read',
          icon: const Icon(Icons.done_all_rounded),
          onPressed: onMarkRead,
        ),
        IconButton(
          tooltip: 'Mark unread',
          icon: const Icon(Icons.remove_done_rounded),
          onPressed: onMarkUnread,
        ),
        IconButton(
          tooltip: 'Keep offline (sync)',
          icon: const Icon(Icons.download_for_offline_outlined),
          onPressed: onKeepOffline,
        ),
        IconButton(
          tooltip: 'Download to server',
          icon: const Icon(Icons.cloud_download_outlined),
          onPressed: onDownloadToServer,
        ),
      ],
    );
  }
}
