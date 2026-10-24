// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../../utils/motion/reduce_motion.dart';
import '../../../../widgets/confirm_bulk_download_dialog.dart';
import '../../../../widgets/download_presets_menu.dart';
import '../../../../widgets/emoticons.dart';
import '../../../../widgets/selection_action_bar.dart';
import '../../../../widgets/shell/update_banner_state.dart';
import '../../../account/data/account_permission.dart';
import '../../../account/data/account_providers.dart';
import '../../../auth/data/auth_credentials_store.dart';
import '../../../manga_book/data/downloads/downloads_repository.dart';
import '../../../manga_book/data/manga_book/manga_book_repository.dart';
import '../../../manga_book/data/updates/updates_repository.dart';
import '../../../manga_book/domain/chapter/chapter_download_presets.dart';
import '../../../manga_book/domain/chapter/chapter_model.dart';
import '../../../manga_book/domain/manga/manga_model.dart';
import '../../../manga_book/presentation/manga_details/controller/scanlator_dedup.dart';
import '../../../manga_book/presentation/manga_details/widgets/edit_manga_category_dialog.dart';
import '../../../migration/domain/migration_models.dart';
import '../../../offline/data/offline_chapter_catchup.dart';
import '../../../offline/data/offline_database.dart';
import '../../../offline/data/offline_download_providers.dart';
import '../../../offline/data/offline_repository.dart';
import '../../../offline/data/offline_runtime_storage.dart';
import '../../../offline/data/server_reachability.dart';
import '../../../offline/presentation/keep_rule_picker.dart';
import '../../../offline/presentation/offline_view_loading.dart';
import '../../../tracking/domain/track_progress_gate.dart';
import 'controller/library_controller.dart';
import 'controller/library_manga_list.dart';
import 'widgets/edit_mangas_category_dialog.dart';
import 'widgets/library_manga_grid_view.dart';

List<int> serverDownloadIds(
  List<ChapterDto>? chapters, {
  DownloadPreset preset = DownloadPreset.all,
  List<String> preferredScanlators = const [],
}) {
  final candidates = chapters ?? const <ChapterDto>[];
  final filtered = preset == DownloadPreset.all
      ? candidates
      : filterPreferredScanlators(candidates, preferredScanlators);
  return chaptersToQueueForPreset([
    for (final chapter in filtered)
      ChapterDownloadCandidate(
        id: chapter.id,
        chapterNumber: chapter.chapterNumber,
        isRead: chapter.user.isRead,
        isDownloaded: chapter.user.isDownloaded,
      ),
  ], preset);
}

class CategoryMangaList extends HookConsumerWidget {
  const CategoryMangaList({super.key, required this.categoryId});
  final int categoryId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canDownload = ref
        .watch(settledAccountAccessProvider)
        .allows(Enum$UserPermission.DOWNLOAD_CHAPTERS);
    final provider = categoryMangaListWithQueryAndFilterProvider(
      categoryId: categoryId,
    );
    final mangaList = ref.watch(provider);
    refresh() => ref.invalidate(categoryMangaListProvider(categoryId));
    useEffect(() {
      // Effects run during build, when provider invalidation is forbidden.
      if (mangaList.isNotLoading) {
        Future.microtask(() {
          if (context.mounted) refresh();
        });
      }
      return;
    }, []);

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

    Future<void> markSelection(bool read) async {
      final ids = selection.value.toList();
      selection.value = const {};
      final repo = ref.read(mangaBookRepositoryProvider);
      final offlineDb = ref.read(offlineReadDatabaseProvider);
      // Capture container.read before awaits so tracker pushes remain valid after widget disposal.
      final containerRead = ProviderScope.containerOf(
        context,
        listen: false,
      ).read;
      var allOk = true;
      for (final id in ids) {
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
          // Persist local read state before the server write so offline changes survive restart.
          final ok = await recordReadState(ref, chapterIds: cids, isRead: read);
          if (!ok) allOk = false;
          // Bulk mark-read bypasses the reader, so tracker progress needs an explicit push.
          if (read && ok) {
            unawaited(
              maybeTrackProgressOnReadFetch(
                containerRead,
                mangaId: id,
                isRead: true,
                manual: true,
              ),
            );
          }
        }
      }
      // refresh() only re-buckets cached DTOs; unreadCount needs a refetch.
      ref.invalidate(libraryMangaListProvider);
      refresh();
      if (!context.mounted) return;
      // Offline failures are queued locally; otherwise a failed server write must surface.
      if (!allOk && !ref.read(offlineActiveProvider)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.errorSomethingWentWrong)),
          snackBarAnimationStyle: context.snackBarMotionStyle,
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
        snackBarAnimationStyle: context.snackBarMotionStyle,
      );
    }

    return mangaList.showUiWhenData(
      // Each tab loads independently and needs its own offline escape hatch.
      loadingWidget: const OfflineViewLoading(),
      offlineEscapeHatch: true,
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
        final Widget grid = LibraryMangaGridView(
          items: items,
          selection: selection.value,
          onOpen: open,
          onLongPress: (manga) => toggle(manga.id),
          linkLocationFor: (manga) =>
              MangaRoute(mangaId: manga.id, categoryId: categoryId).location,
        );

        final list = RefreshIndicator(
          // The spinner waits for the immediate re-read; update completion triggers another refresh.
          onRefresh: () async {
            // Only a user gesture may clear the offline pin, never the mount effect.
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
                    onKeepOffline: !canDownload
                        ? null
                        : () async {
                            final current = ref
                                .read(authCredentialsStoreProvider.notifier)
                                .captureSession();
                            final ids = selection.value.toList();
                            // Capture the container while context is mounted, before opening dialogs.
                            final container = ProviderScope.containerOf(
                              context,
                              listen: false,
                            );
                            final picked = await pickOfflineKeepRule(context);
                            if (picked == null) return;

                            if (picked.remove) {
                              if (!context.mounted) return;
                              final ok =
                                  await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      icon: Icon(
                                        Icons.delete_outline_rounded,
                                        color: ctx.theme.colorScheme.error,
                                      ),
                                      title: Text(
                                        ctx.l10n.manageDownloadsStopDelete,
                                      ),
                                      content: Text(
                                        ctx.l10n.manageDownloadsDeleteConfirm(
                                          ids.length,
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, false),
                                          child: Text(ctx.l10n.cancel),
                                        ),
                                        FilledButton(
                                          style: FilledButton.styleFrom(
                                            backgroundColor:
                                                ctx.theme.colorScheme.error,
                                          ),
                                          onPressed: () =>
                                              Navigator.pop(ctx, true),
                                          child: Text(ctx.l10n.delete),
                                        ),
                                      ],
                                    ),
                                    animationStyle: context.motionStyle,
                                  ) ??
                                  false;
                              if (!ok || !current()) return;
                              selection.value = const {};
                              for (final id in ids) {
                                if (!current()) return;
                                await removeKeepRuleAndDelete(ref, id);
                              }
                              return;
                            }

                            if (picked.rule == OfflineKeepRule.off) {
                              // changeKeepRule also rewrites background work; bare setKeepRule leaves downloads scheduled.
                              if (!current()) return;
                              selection.value = const {};
                              for (final id in ids) {
                                if (!current()) return;
                                await changeKeepRule(
                                  ref,
                                  id,
                                  OfflineKeepRule.off,
                                  5,
                                );
                              }
                              return;
                            }

                            if (ids.length > 1 &&
                                context.mounted &&
                                !await confirmBulkDownload(
                                  context,
                                  summary: '${ids.length} series',
                                  toDevice: true,
                                )) {
                              return;
                            }
                            if (!context.mounted || !current()) return;
                            selection.value = const {};
                            ref
                                .read(accountPermissionGuardProvider)
                                .require(Enum$UserPermission.DOWNLOAD_CHAPTERS);
                            final db = ref.read(offlineDatabaseProvider);
                            final sync = ref.read(offlineSyncProvider);
                            final runtime = ref.read(
                              offlineRuntimeStorageProvider.notifier,
                            );
                            // setKeepRule only updates existing rows; mirror selected manga before setting their rules.
                            final selected = items
                                .where((m) => ids.contains(m.id))
                                .toList();
                            for (final manga in selected) {
                              if (!current()) return;
                              await runtime.track(() async {
                                await sync?.syncManga(
                                  manga,
                                  fetchedAtGen: sync.syncGeneration,
                                );
                                await db.setKeepRule(
                                  manga.id,
                                  picked.rule,
                                  picked.count,
                                );
                              });
                            }
                            if (!current()) return;
                            // Refresh serverIsDownloaded before reconciliation so downloads take the correct server/device route.
                            unawaited(
                              syncAndReconcileMangaSet(
                                container,
                                ids.toSet(),
                                userInitiated: true,
                              ),
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Keeping ${ids.length} series offline',
                                  ),
                                ),
                                snackBarAnimationStyle:
                                    context.snackBarMotionStyle,
                              );
                            }
                          },
                    onDownloadToServer: !canDownload
                        ? null
                        : (preset) async {
                            final current = ref
                                .read(authCredentialsStoreProvider.notifier)
                                .captureSession();
                            final ids = selection.value.toList();
                            final library =
                                ref.read(libraryMangaListProvider).value ??
                                items;
                            final preferences = {
                              for (final manga in library)
                                if (ids.contains(manga.id))
                                  manga.id: manga
                                      .metaData
                                      .effectivePreferredScanlators,
                            };
                            if (ids.length > 1 &&
                                !await confirmBulkDownload(
                                  context,
                                  summary: '${ids.length} series',
                                  toDevice: false,
                                  downloadDescription: context.l10n
                                      .bulkDownloadPresetDescription(
                                        downloadPresetLabel(context, preset),
                                      ),
                                )) {
                              return;
                            }
                            if (!context.mounted || !current()) return;
                            selection.value = const {};
                            final repo = ref.read(mangaBookRepositoryProvider);
                            final dl = ref.read(downloadsRepositoryProvider);
                            if (!context.mounted || !current()) return;
                            var queuedAny = false;
                            final result = await AsyncValue.guard(() async {
                              for (final id in ids) {
                                if (!context.mounted || !current()) return;
                                final chapters = await repo.getChapterList(id);
                                if (!context.mounted || !current()) return;
                                final chapterIds = serverDownloadIds(
                                  chapters,
                                  preset: preset,
                                  preferredScanlators:
                                      preferences[id] ?? const [],
                                );
                                if (chapterIds.isNotEmpty) {
                                  await dl.addChaptersBatchToDownloadQueue(
                                    chapterIds,
                                  );
                                  queuedAny = true;
                                }
                              }
                            });
                            if (!context.mounted || !current()) return;
                            if (result.hasError) {
                              result.showToastOnError(ref.read(toastProvider));
                              return;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  queuedAny
                                      ? 'Downloading ${ids.length} series to server'
                                      : context.l10n.nothingToDownload,
                                ),
                              ),
                              snackBarAnimationStyle:
                                  context.snackBarMotionStyle,
                            );
                          },
                    onEditCategories: () async {
                      final selected = items
                          .where((m) => selection.value.contains(m.id))
                          .toList();
                      if (selected.isEmpty) return;
                      selection.value = const {};
                      await showDialog<void>(
                        context: context,
                        builder: (context) => selected.length == 1
                            ? EditMangaCategoryDialog(
                                mangaId: selected.first.id,
                                title: selected.first.title,
                              )
                            : EditMangasCategoryDialog(mangas: selected),
                        animationStyle: context.motionStyle,
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
      },
      refresh: refresh,
    );
  }
}

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
  final VoidCallback? onKeepOffline;
  final ValueChanged<DownloadPreset>? onDownloadToServer;
  final VoidCallback onEditCategories;
  final VoidCallback onMigrate;

  PopupMenuItem<VoidCallback> _moreItem(
    IconData icon,
    String label,
    VoidCallback? onTap,
  ) => PopupMenuItem<VoidCallback>(
    enabled: onTap != null,
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
        DownloadPresetsMenu(onSelected: onDownloadToServer),
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
          popUpAnimationStyle: context.motionStyle,
        ),
      ],
    );
  }
}
