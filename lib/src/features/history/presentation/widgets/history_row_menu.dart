// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/app_sizes.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../../utils/motion/reduce_motion.dart';
import '../../../manga_book/domain/chapter/chapter_model.dart';
import '../../../manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import '../../../manga_book/presentation/manga_details/widgets/add_to_library_category.dart';
import '../../../manga_book/presentation/manga_details/widgets/chapter_context_menu.dart';
import '../../../manga_book/presentation/updates/widgets/updates_row_actions.dart';
import '../../../manga_book/widgets/chapter_actions/chapter_bulk_actions.dart';
import '../../../offline/data/offline_download_providers.dart';
import '../../../offline/data/offline_repository.dart';
import '../../../offline/data/offline_types.dart';
import '../../domain/history_item.dart';
import '../history_controller.dart';

Future<void> addHistorySeriesToLibrary(
  WidgetRef ref,
  BuildContext context,
  int mangaId,
) async {
  final toast = ref.read(toastProvider);
  final result = await AsyncValue.guard(() async {
    final manga = await ref.read(mangaWithIdProvider(mangaId: mangaId).future);
    if (!context.mounted) return;
    if (manga == null) {
      toast?.showError(context.l10n.errorSomethingWentWrong);
      return;
    }
    await addMangaToLibraryWithCategory(ref, context, manga);
  });
  if (!context.mounted) return;
  result.showToastOnError(toast);
}

Future<void> _markHistoryPreviousAsRead(
  WidgetRef ref,
  BuildContext context,
  HistoryItemDto item,
) async {
  final bulk = await loadSeriesChapters(ref, item.mangaId);
  if (!context.mounted) return;
  if (bulk == null) {
    ref.read(toastProvider)?.showError(context.l10n.errorSomethingWentWrong);
    return;
  }
  await markPreviousAsRead(
    context: context,
    ref: ref,
    bulkList: bulk,
    anchor: item,
    refresh: (_) => refreshHistory(ref),
  );
}

Future<void> refreshHistory(WidgetRef ref) =>
    ref.read(readingHistoryProvider.notifier).refresh();

Future<void> showHistoryChapterMenu({
  required BuildContext context,
  required WidgetRef ref,
  required RelativeRect position,
  required HistoryItemDto item,
  void Function()? refocus,
}) => showChapterContextMenu(
  context: context,
  ref: ref,
  position: position,
  seriesUrl: null,
  chapter: item,
  selectedChapters: ValueNotifier<Map<int, ChapterDto>>({}),
  selectionAnchor: ValueNotifier<int?>(null),
  orderedChapters: const [],
  bulkChapters: const [],
  loadBulkChapters: () => loadSeriesChapters(ref, item.mangaId),
  refresh: () => refreshHistory(ref),
  refocus: refocus,
  historyMenu: true,
  onViewManga: () async {
    await MangaRoute(mangaId: item.mangaId).push(context);
    if (!context.mounted) return;
    await refreshHistory(ref);
  },
  onAddToLibrary: item.manga.user.inLibrary
      ? null
      : () => addHistorySeriesToLibrary(ref, context, item.mangaId),
);

Future<void> showHistoryActionsSheet({
  required BuildContext context,
  required WidgetRef ref,
  required HistoryItemDto item,
}) {
  final read = item.user.isRead;
  final bookmarked = item.user.isBookmarked;
  final downloaded = item.user.isDownloaded;
  final inLibrary = item.manga.user.inLibrary;
  final canDownload = canDownloadChapters(ref);
  final offlineEnabled = ref.read(offlineEnabledProvider);
  final onDevice =
      ref.read(offlineChapterStateProvider(item.id)).value ==
      OfflineDeviceState.downloaded;
  final hasBrowserTarget = chapterHasBrowserTarget(item, null);

  Future<void> afterSheet(Future<void> Function() action) async {
    if (!context.mounted) return;
    await action();
  }

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: RoundedRectangleBorder(borderRadius: KBorderRadius.rT16.radius),
    clipBehavior: Clip.hardEdge,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            leading: const Icon(FluentIcons.book_open_24_regular),
            title: Text(context.l10n.viewManga),
            onTap: () async {
              Navigator.pop(sheetContext);
              await MangaRoute(mangaId: item.mangaId).push(context);
              await afterSheet(() => refreshHistory(ref));
            },
          ),
          if (!inLibrary)
            ListTile(
              leading: const Icon(FluentIcons.heart_24_regular),
              title: Text(context.l10n.addToLibrary),
              onTap: () async {
                Navigator.pop(sheetContext);
                await afterSheet(() async {
                  await addHistorySeriesToLibrary(ref, context, item.mangaId);
                  await refreshHistory(ref);
                });
              },
            ),
          ListTile(
            leading: Icon(
              bookmarked
                  ? FluentIcons.bookmark_24_filled
                  : FluentIcons.bookmark_24_regular,
            ),
            title: Text(
              bookmarked ? context.l10n.removeBookmark : context.l10n.bookmark,
            ),
            onTap: () async {
              Navigator.pop(sheetContext);
              await afterSheet(() async {
                await toggleChapterBookmark(ref, item);
                await refreshHistory(ref);
              });
            },
          ),
          ListTile(
            leading: const Icon(Icons.done_rounded),
            title: Text(
              read ? context.l10n.markAsUnread : context.l10n.markAsRead,
            ),
            onTap: () async {
              Navigator.pop(sheetContext);
              await afterSheet(
                () => markChaptersRead(
                  context: context,
                  ref: ref,
                  chapters: [item],
                  isRead: !read,
                  refresh: (_) => refreshHistory(ref),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(
              FluentIcons.text_bullet_list_checkmark_20_regular,
            ),
            title: Text(context.l10n.markPreviousAsRead),
            onTap: () async {
              Navigator.pop(sheetContext);
              await afterSheet(
                () => _markHistoryPreviousAsRead(ref, context, item),
              );
            },
          ),
          if (hasBrowserTarget)
            ListTile(
              leading: const Icon(FluentIcons.globe_24_regular),
              title: Text(context.l10n.openInBrowser),
              onTap: () {
                Navigator.pop(sheetContext);
                openChapterInBrowser(context, ref, item, null);
              },
            ),
          if (offlineEnabled)
            ListTile(
              leading: Icon(
                onDevice
                    ? FluentIcons.checkmark_circle_24_filled
                    : FluentIcons.arrow_circle_down_24_regular,
              ),
              title: Text(
                onDevice
                    ? context.l10n.removeFromDevice
                    : context.l10n.keepOffline,
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                await afterSheet(() async {
                  if (onDevice) {
                    await removeChapterFromDevice(ref, item.id);
                  } else {
                    try {
                      await keepChapterOffline(ref, item.id);
                    } catch (_) {
                      if (context.mounted) {
                        ref
                            .read(toastProvider)
                            ?.showError(context.l10n.errorSomethingWentWrong);
                      }
                    }
                  }
                  await refreshHistory(ref);
                });
              },
            ),
          if (!downloaded)
            ListTile(
              leading: const Icon(FluentIcons.cloud_arrow_down_24_regular),
              title: Text(context.l10n.download),
              enabled: canDownload,
              onTap: () async {
                Navigator.pop(sheetContext);
                await afterSheet(
                  () => queueServerDownload(
                    context: context,
                    ref: ref,
                    chapterIds: [item.id],
                    refresh: (_) => refreshHistory(ref),
                  ),
                );
              },
            ),
        ],
      ),
    ),
    sheetAnimationStyle: context.motionStyle,
  );
}
