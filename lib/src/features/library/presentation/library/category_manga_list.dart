// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/confirm_bulk_download_dialog.dart';
import '../../../../widgets/emoticons.dart';
import '../../../../widgets/selection_action_bar.dart';
import '../../../../widgets/shell/update_banner_state.dart';
import '../../../manga_book/data/downloads/downloads_repository.dart';
import '../../../manga_book/data/manga_book/manga_book_repository.dart';
import '../../../manga_book/data/updates/updates_repository.dart';
import '../../../manga_book/domain/manga/manga_model.dart';
import '../../../manga_book/presentation/manga_details/widgets/edit_manga_category_dialog.dart';
import '../../../migration/domain/migration_models.dart';
import '../../../offline/data/offline_download_providers.dart';
import '../../../offline/data/offline_repository.dart';
import '../../../offline/data/server_reachability.dart';
import '../../../offline/presentation/keep_rule_picker.dart';
import '../../../offline/presentation/offline_view_loading.dart';
import '../../../tracking/domain/track_progress_gate.dart';
import 'controller/library_controller.dart';
import 'controller/library_manga_list.dart';
import 'widgets/edit_mangas_category_dialog.dart';
import 'widgets/library_manga_grid_view.dart';

class CategoryMangaList extends HookConsumerWidget {
  const CategoryMangaList({super.key, required this.categoryId});
  final int categoryId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = categoryMangaListWithQueryAndFilterProvider(
      categoryId: categoryId,
    );
    final mangaList = ref.watch(provider);
    refresh() => ref.invalidate(categoryMangaListProvider(categoryId));
    useEffect(() {
      // Effect bodies run during build; invalidating a provider there throws.
      if (mangaList.isNotLoading) {
        Future.microtask(() {
          if (context.mounted) refresh();
        });
      }
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

    // Mark every chapter of the selected series read / unread, via the bulk
    // chapter mutation (one batch per series).
    Future<void> markSelection(bool read) async {
      final ids = selection.value.toList();
      selection.value = const {};
      final repo = ref.read(mangaBookRepositoryProvider);
      final offlineDb = ref.read(offlineReadDatabaseProvider);
      var allOk = true;
      for (final id in ids) {
        // Server first; offline, fall back to the catalog chapter rows
        // instead of failing the whole series silently.
        List<int> cids;
        try {
          final chapters = await repo.getChapterList(id);
          cids = <int>[for (final c in chapters ?? const []) c.id];
        } catch (_) {
          if (offlineDb == null) {
            allOk = false;
            continue;
          }
          cids = [for (final c in await offlineDb.chaptersForManga(id)) c.id];
        }
        if (cids.isNotEmpty) {
          // Offline-aware write-through: the local rows are updated first (so
          // the change survives offline + restart and keeps Resume truthful),
          // then the server bulk write — same fix as the chapter-list icons.
          final ok = await recordReadState(ref, chapterIds: cids, isRead: read);
          if (!ok) allOk = false;
          // Marking a whole series read here bypasses the reader, so push the
          // new progress to the bound tracker(s) explicitly (manual path).
          if (read && ok) {
            unawaited(
              maybeTrackProgressOnReadFetch(
                ref,
                mangaId: id,
                isRead: true,
                manual: true,
              ),
            );
          }
        }
      }
      // refresh() only re-buckets cached DTOs; unreadCount needs a real refetch.
      ref.invalidate(libraryMangaListProvider);
      refresh();
      if (!context.mounted) return;
      // A server failure with offline inactive means nothing was persisted, so
      // surface it instead of a false success. (An offline-active failure is
      // queued locally and up-syncs later, so the success message still holds.)
      if (!allOk && !ref.read(offlineActiveProvider)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.errorSomethingWentWrong)),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            read
                ? 'Marked ${ids.length} series read'
                : 'Marked ${ids.length} series unread',
          ),
        ),
      );
    }

    return mangaList.showUiWhenData(
        // Own loading state per tab, so the offline escape hatch needs to
        // live here too, not only on the library-level gates.
        loadingWidget: const OfflineViewLoading(),
        offlineEscapeHatch: true,
        context, (data) {
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
      final Widget grid = LibraryMangaGridView(
        items: items,
        selection: selection.value,
        onOpen: open,
        onLongPress: (manga) => toggle(manga.id),
      );

      final list = RefreshIndicator(
        // Pull = "check this category for new chapters, and pull down the
        // latest" (Mihon/Komikku parity). The source-check runs server-side
        // and the progress banner reflects it, so the spinner only waits on
        // the immediate re-read, not the whole update. The standing rule in
        // LibraryScreen re-reads again when the update finishes.
        onRefresh: () async {
          // A pull means "try the server again" — drop the offline pin.
          // Only a user gesture clears it; the mount effect must not.
          ref.read(viewOfflineNowProvider.notifier).set(false);
          ref.read(serverUnreachableProvider.notifier).set(false);
          ref.read(updateOptimisticProvider.notifier).arm();
          unawaited(
            ref
                .read(updatesRepositoryProvider)
                .fetchUpdates(categoryId: categoryId)
                .catchError((Object _) {}),
          );
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
                        !await confirmBulkDownload(
                          context,
                          summary: '${ids.length} series',
                          toDevice: true,
                        )) {
                      return;
                    }
                    selection.value = const {};
                    final db = ref.read(offlineDatabaseProvider);
                    for (final id in ids) {
                      await db.setKeepRule(id, picked.rule, picked.count);
                      // Queue only — starting per manga let the FGS drain and
                      // stop between each one, so its "X/Y" notification never
                      // showed the whole selection's real total. One start
                      // below, after every manga in the selection is queued.
                      await reconcileMangaWidget(ref, id, startDownload: false);
                    }
                    await ref.read(downloadStarterProvider)(
                      userInitiated: true,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Keeping ${ids.length} series offline'),
                        ),
                      );
                    }
                  },
                  onDownloadToServer: () async {
                    final ids = selection.value.toList();
                    if (ids.length > 1 &&
                        !await confirmBulkDownload(
                          context,
                          summary: '${ids.length} series',
                          toDevice: false,
                        )) {
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Downloading ${ids.length} series to server',
                          ),
                        ),
                      );
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
                  onMigrate: () {
                    final ids = selection.value.toList();
                    if (ids.isEmpty) return;
                    selection.value = const {};
                    MigrationBulkConfigRoute(
                      $extra: MigrationBulkConfigData(mangaIds: ids),
                    ).push(context);
                  },
                ),
              ),
          ],
        ),
      );
    }, refresh: refresh);
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
    required this.onMigrate,
  });

  final int count;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;
  final VoidCallback onMarkRead;
  final VoidCallback onMarkUnread;
  final VoidCallback onKeepOffline;
  final VoidCallback onDownloadToServer;
  final VoidCallback onEditCategories;
  final VoidCallback onMigrate;

  PopupMenuItem<VoidCallback> _moreItem(
    IconData icon,
    String label,
    VoidCallback onTap,
  ) => PopupMenuItem<VoidCallback>(
    value: onTap,
    child: Row(children: [Icon(icon), const SizedBox(width: 12), Text(label)]),
  );

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
      // Komikku LibraryBottomActionMenu shape: a few primary actions inline, the
      // rest in a "More" (⋮) overflow — so the bar never clips on a phone.
      actions: [
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
          tooltip: 'Download to server',
          icon: const Icon(Icons.cloud_download_outlined),
          onPressed: onDownloadToServer,
        ),
        PopupMenuButton<VoidCallback>(
          tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
          icon: const Icon(Icons.more_vert),
          onSelected: (action) => action(),
          itemBuilder: (context) => [
            _moreItem(Icons.select_all_rounded, 'Select all', onSelectAll),
            _moreItem(Icons.save_alt_rounded, 'Keep on device', onKeepOffline),
            _moreItem(
              Icons.swap_horiz,
              context.l10n.bulkMigrationTitle,
              onMigrate,
            ),
          ],
        ),
      ],
    );
  }
}
