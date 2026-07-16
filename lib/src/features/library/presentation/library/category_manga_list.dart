// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/app_sizes.dart';
import '../../../../constants/enum.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/confirm_bulk_download_dialog.dart';
import '../../../../widgets/emoticons.dart';
import '../../../../widgets/manga_cover/grid/manga_cover_grid_tile.dart';
import '../../../../widgets/manga_cover/list/manga_cover_descriptive_list_tile.dart';
import '../../../../widgets/manga_cover/list/manga_cover_list_tile.dart';
import '../../../../widgets/manga_cover/providers/manga_cover_providers.dart';
import '../../../../widgets/selection_action_bar.dart';
import '../../../../widgets/shell/update_banner_state.dart';
import '../../../manga_book/data/downloads/downloads_repository.dart';
import '../../../manga_book/data/manga_book/manga_book_repository.dart';
import '../../../manga_book/data/updates/updates_repository.dart';
import '../../../manga_book/domain/manga/manga_model.dart';
import '../../../manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import '../../../manga_book/presentation/manga_details/widgets/edit_manga_category_dialog.dart';
import '../../../offline/data/offline_download_providers.dart';
import '../../../offline/data/offline_repository.dart';
import '../../../offline/presentation/keep_rule_picker.dart';
import '../../../settings/presentation/appearance/widgets/grid_cover_width_slider/grid_cover_width_slider.dart';
import '../../../tracking/domain/track_progress_gate.dart';
import 'controller/library_controller.dart';
import 'controller/library_manga_list.dart';
import 'widgets/edit_mangas_category_dialog.dart';

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
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final portraitCols = ref.watch(libraryPortraitColumnsProvider) ?? 0;
    final landscapeCols = ref.watch(libraryLandscapeColumnsProvider) ?? 0;
    final fixedCols = isLandscape ? landscapeCols : portraitCols;
    // gridDelegate: fixed count when the user set cols > 0, else Auto (width-based).
    SliverGridDelegate libraryGridDelegate({bool titleBelow = false}) =>
        fixedCols > 0
            ? SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: fixedCols,
                crossAxisSpacing: 2.0,
                mainAxisSpacing: 2.0,
                childAspectRatio: titleBelow ? 0.62 : 0.75,
              )
            : mangaCoverGridDelegate(gridWidth, titleBelow: titleBelow);
    refresh() => ref.invalidate(categoryMangaListProvider(categoryId));
    useEffect(() {
      if (mangaList.isNotLoading) refresh();
      return;
    }, []);

    // Multi-select: long-press starts selection, tap toggles
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

    // Continue-reading button: opt-in display toggle. Shown only when the server
    // (or offline catalog) reports a next-unread chapter, and never while
    // multi-selecting (taps belong to selection then). Opens that chapter
    // straight in the reader, bypassing the details page.
    final showContinueReading =
        ref.watch(showContinueReadingButtonProvider).ifNull(false);
    VoidCallback? continueReadingFor(MangaDto manga) {
      if (!showContinueReading || selecting) return null;
      final chapter = manga.firstUnreadChapter;
      if (chapter == null) return null;
      return () {
        unawaited(() async {
          await AsyncValue.guard(
            () => ref.read(
              mangaChapterListProvider(mangaId: manga.id).future,
            ),
          );
          if (!context.mounted) return;
          ReaderRoute(mangaId: manga.id, chapterId: chapter.id).push(context);
        }());
      };
    }

    // Mark every chapter of the selected series read / unread, via the bulk
    // chapter mutation (one batch per series).
    Future<void> markSelection(bool read) async {
      final ids = selection.value.toList();
      selection.value = const {};
      final repo = ref.read(mangaBookRepositoryProvider);
      var allOk = true;
      for (final id in ids) {
        final chapters = await repo.getChapterList(id);
        final cids = <int>[for (final c in chapters ?? const []) c.id];
        if (cids.isNotEmpty) {
          // Offline-aware write-through: the local rows are updated first (so
          // the change survives offline + restart and keeps Resume truthful),
          // then the server bulk write — same fix as the chapter-list icons.
          final ok = await recordReadState(ref, chapterIds: cids, isRead: read);
          if (!ok) allOk = false;
          // Marking a whole series read here bypasses the reader, so push the
          // new progress to the bound tracker(s) explicitly (manual path).
          if (read && ok) {
            unawaited(maybeTrackProgressOnReadFetch(
              ref,
              mangaId: id,
              isRead: true,
              manual: true,
            ));
          }
        }
      }
      refresh();
      if (!context.mounted) return;
      // A server failure with offline inactive means nothing was persisted, so
      // surface it instead of a false success. (An offline-active failure is
      // queued locally and up-syncs later, so the success message still holds.)
      if (!allOk && !ref.read(offlineActiveProvider)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.l10n.errorSomethingWentWrong),
        ));
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(read
            ? 'Marked ${ids.length} series read'
            : 'Marked ${ids.length} series unread'),
      ));
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
                onContinueReading: continueReadingFor(items[index]),
                showCountBadges: true,
              ),
            ),
          DisplayMode.grid => GridView.builder(
              gridDelegate: libraryGridDelegate(),
              itemCount: items.length,
              itemBuilder: (context, index) => MangaCoverGridTile(
                manga: items[index],
                selected: selection.value.contains(items[index].id),
                onLongPress: () => toggle(items[index].id),
                onPressed: () => open(items[index]),
                onContinueReading: continueReadingFor(items[index]),
                showCountBadges: true,
                showDarkOverlay: false,
              ),
            ),
          DisplayMode.comfortableGrid => GridView.builder(
              gridDelegate: libraryGridDelegate(titleBelow: true),
              itemCount: items.length,
              itemBuilder: (context, index) => MangaCoverGridTile(
                manga: items[index],
                selected: selection.value.contains(items[index].id),
                onLongPress: () => toggle(items[index].id),
                onPressed: () => open(items[index]),
                onContinueReading: continueReadingFor(items[index]),
                showCountBadges: true,
                titleBelow: true,
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
                onContinueReading: continueReadingFor(items[index]),
                showBadges: true,
              ),
            ),
          DisplayMode.coverOnly => GridView.builder(
              gridDelegate: libraryGridDelegate(),
              itemCount: items.length,
              itemBuilder: (context, index) => MangaCoverGridTile(
                manga: items[index],
                selected: selection.value.contains(items[index].id),
                onLongPress: () => toggle(items[index].id),
                onPressed: () => open(items[index]),
                onContinueReading: continueReadingFor(items[index]),
                showCountBadges: true,
                showTitle: false,
                showDarkOverlay: false,
              ),
            ),
        };

        final list = RefreshIndicator(
          // Pull = "check this category for new chapters, and pull down the
          // latest" (Mihon/Komikku parity). The source-check runs server-side
          // and the progress banner reflects it, so the spinner only waits on
          // the immediate re-read, not the whole update. The standing rule in
          // LibraryScreen re-reads again when the update finishes.
          onRefresh: () async {
            ref.read(updateOptimisticProvider.notifier).arm();
            unawaited(ref
                .read(updatesRepositoryProvider)
                .fetchUpdates(categoryId: categoryId)
                .catchError((Object _) {}));
            ref.invalidate(libraryMangaListProvider);
            await ref.read(libraryMangaListProvider.future);
          },
          child: grid,
        );

        // While selecting, swallow the system back to exit selection first, and
        // show a contextual action bar over the grid.
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
                      // Let the user choose how much to keep (next-N / all-unread
                      // / all) instead of silently downloading every chapter —
                      // picking "all" across a read library can queue thousands.
                      final picked = await pickOfflineKeepRule(context);
                      if (picked == null) return;
                      if (ids.length > 1 &&
                          context.mounted &&
                          !await confirmBulkDownload(context,
                              summary: '${ids.length} series',
                              toDevice: true)) {
                        return;
                      }
                      selection.value = const {};
                      final db = ref.read(offlineDatabaseProvider);
                      for (final id in ids) {
                        await db.setKeepRule(id, picked.rule, picked.count);
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
                      if (ids.length > 1 &&
                          !await confirmBulkDownload(context,
                              summary: '${ids.length} series',
                              toDevice: false)) {
                        return;
                      }
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
                          content: Text(
                              'Downloading ${ids.length} series to server'),
                        ));
                      }
                    },
                    onEditCategories: () async {
                      final selected = items
                          .where((m) => selection.value.contains(m.id))
                          .toList();
                      if (selected.isEmpty) return;
                      selection.value = const {};
                      // One series → the per-series toggle dialog; many → the
                      // bulk tri-state dialog.
                      await showDialog<void>(
                        context: context,
                        builder: (context) => selected.length == 1
                            ? EditMangaCategoryDialog(
                                mangaId: selected.first.id,
                                title: selected.first.title,
                              )
                            : EditMangasCategoryDialog(mangas: selected),
                      );
                      refresh();
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

/// Bottom action bar shown while library manga are multi-selected: mark
/// read/unread, edit categories (bulk), keep offline, and download to server.
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
          tooltip: 'Keep on device (sync)',
          icon: const Icon(Icons.save_alt_rounded),
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
