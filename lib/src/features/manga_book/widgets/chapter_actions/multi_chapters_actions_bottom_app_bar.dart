// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../features/offline/data/offline_download_providers.dart';
import '../../../../features/offline/data/offline_repository.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../../widgets/selection_action_bar.dart';
import '../../data/downloads/downloads_repository.dart';
import '../../data/manga_book/manga_book_repository.dart';
import '../../domain/chapter/chapter_model.dart';
import '../../domain/chapter_batch/chapter_batch_model.dart';
import 'multi_chapters_action_icon.dart';

class MultiChaptersActionsBottomAppBar extends HookConsumerWidget {
  const MultiChaptersActionsBottomAppBar({
    super.key,
    required this.selectedChapters,
    required this.afterOptionSelected,
    this.chapterList,
  });

  final ValueNotifier<Map<int, ChapterDto>> selectedChapters;
  final AsyncCallback afterOptionSelected;
  final List<ChapterDto>? chapterList;

  List<int> get selectedChapterList => selectedChapters.value.keys.toList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    refresh([bool triggerAfterOption = true]) async {
      selectedChapters.value = {};
      if (triggerAfterOption) await afterOptionSelected();
    }

    // Same floating action bar as the library multi-select, with parity actions:
    // a leading clear + count, then mark read / unread, download to device,
    // download to server, and delete.
    return SelectionActionBar(
      clearsSystemNav: true,
      leading: [
        IconButton(
          tooltip: 'Clear',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => refresh(false),
        ),
        Text('${selectedChapters.value.length}',
            style: context.textTheme.titleMedium),
      ],
      actions: [
        IconButton(
          tooltip: 'Select all',
          icon: const Icon(Icons.select_all_rounded),
          onPressed: chapterList == null
              ? null
              : () => selectedChapters.value = {
                    for (final c in chapterList!) c.id: c,
                  },
        ),
        MultiChaptersActionIcon(
          iconData: Icons.done_all_rounded,
          chapterList: selectedChapterList,
          change: ChapterChange(isRead: true, lastPageRead: 0),
          refresh: refresh,
        ),
        MultiChaptersActionIcon(
          iconData: Icons.remove_done_rounded,
          chapterList: selectedChapterList,
          change: ChapterChange(isRead: false),
          refresh: refresh,
        ),
        IconButton(
          tooltip: context.l10n.keepOffline,
          icon: const Icon(Icons.download_for_offline_outlined),
          onPressed: () async {
            // Download FIRST, clear selection AFTER: clearing selection disposes
            // this bar, which would invalidate `ref` mid-loop and silently drop
            // the remaining downloads.
            final ids = selectedChapterList;
            for (final id in ids) {
              await saveChapterToDevice(ref, id);
            }
            await refresh(true);
          },
        ),
        IconButton(
          tooltip: context.l10n.downloads,
          icon: const Icon(Icons.cloud_download_outlined),
          onPressed: () async {
            final result = await AsyncValue.guard(
              () => ref
                  .read(downloadsRepositoryProvider)
                  .addChaptersBatchToDownloadQueue(selectedChapterList),
            );
            if (context.mounted) {
              result.showToastOnError(ref.read(toastProvider));
            }
            await refresh(true);
          },
        ),
        IconButton(
          tooltip: context.l10n.delete,
          icon: const Icon(Icons.delete_rounded),
          onPressed: () async {
            final repo = ref.read(offlineRepositoryProvider);
            final onDevice =
                await repo.deviceDownloadedCount(selectedChapterList);
            if (onDevice > 0) {
              if (!context.mounted) return;
              final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(ctx.l10n.delete),
                      content:
                          Text(ctx.l10n.offlineBulkDeleteWarning(onDevice)),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text(ctx.l10n.cancel)),
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: Text(ctx.l10n.delete)),
                      ],
                    ),
                  ) ??
                  false;
              if (!ok) return;
            }
            final result = await AsyncValue.guard(
              () => ref
                  .read(mangaBookRepositoryProvider)
                  .deleteChapters(selectedChapterList),
            );
            if (context.mounted) {
              result.showToastOnError(ref.read(toastProvider));
            }
            if (!result.hasError) {
              await cascadeServerDeleteToDevice(ref, selectedChapterList);
            }
            await refresh(true);
          },
        ),
      ],
    );
  }
}
