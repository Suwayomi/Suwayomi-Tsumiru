// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../constants/app_sizes.dart';
import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../../../../../widgets/server_image.dart';
import '../../../data/downloads/downloads_repository.dart';
import '../../../domain/downloads/downloads_model.dart';
import '../controller/downloads_controller.dart';

class DownloadProgressListTile extends HookConsumerWidget {
  const DownloadProgressListTile({
    super.key,
    required this.chapterId,
    required this.toast,
    required this.index,
    required this.downloadsCount,
  });
  final int chapterId;
  final Toast? toast;
  final int index;
  final int downloadsCount;

  Future toggleChapterToQueue(
    Toast? toast,
    WidgetRef ref,
    bool addToDownload,
    int chapterId,
  ) async {
    try {
      (await AsyncValue.guard(() async {
        final repo = ref.read(downloadsRepositoryProvider);
        await repo.removeChapterFromDownloadQueue(chapterId);
        if (addToDownload) {
          await repo.addChaptersBatchToDownloadQueue([chapterId]);
        }
      }))
          .showToastOnError(toast);
    } catch (e) {
      //
    }
  }

  String _downloadingText(BuildContext context, DownloadDto downloadUpdate) {
    final total = downloadUpdate.chapter.pageCount;
    if (total > 0) {
      final done = (downloadUpdate.progress * total).round();
      return '${context.l10n.downloading} · '
          '${context.l10n.downloadPagesProgress(done, total)}';
    }
    return '${context.l10n.downloading} · '
        '${(downloadUpdate.progress * 100).toInt()}%';
  }

  String _stateText(BuildContext context, DownloadDto downloadUpdate) =>
      switch (downloadUpdate.state) {
        DownloadState.QUEUED => context.l10n.queued,
        DownloadState.DOWNLOADING => _downloadingText(context, downloadUpdate),
        DownloadState.ERROR ||
        DownloadState.FINISHED =>
          downloadUpdate.toDisplayName(context),
        DownloadState.$unknown => throw UnimplementedError(),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadUpdate = ref.watch(downloadsFromIdProvider(chapterId));
    if (downloadUpdate == null) return const SizedBox.shrink();
    final colorScheme = context.theme.colorScheme;
    final isError = downloadUpdate.state == DownloadState.ERROR;
    final isDownloading = downloadUpdate.state == DownloadState.DOWNLOADING;
    return ReorderableDelayedDragStartListener(
      index: index,
      child: Column(
        children: [
          ListTile(
            isThreeLine: true,
            leading: SizedBox(
              width: 40,
              height: 56,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: ServerImage(
                  imageUrl: downloadUpdate.manga.thumbnailUrl ?? '',
                  fit: BoxFit.cover,
                ),
              ),
            ),
            title: Text(
              downloadUpdate.manga.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  downloadUpdate.chapter.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _stateText(context, downloadUpdate),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isError
                        ? colorScheme.error
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PopupMenuButton(
                  shape: RoundedRectangleBorder(
                    borderRadius: KBorderRadius.r16.radius,
                  ),
                  itemBuilder: (context) => [
                    if (isError)
                      PopupMenuItem(
                        child: Text(context.l10n.retry),
                        onTap: () => toggleChapterToQueue(
                            toast, ref, true, downloadUpdate.chapter.id),
                      ),
                    PopupMenuItem(
                      child: Text(context.l10n.cancel),
                      onTap: () => toggleChapterToQueue(
                          toast, ref, false, downloadUpdate.chapter.id),
                    ),
                    if (!index.isZero)
                      PopupMenuItem(
                        child: Text(context.l10n.moveToTop),
                        onTap: () => ref
                            .read(downloadsMapProvider.notifier)
                            .reorder(downloadUpdate.chapter.id, 0),
                      ),
                    if (index < downloadsCount - 1)
                      PopupMenuItem(
                        child: Text(context.l10n.moveToBottom),
                        onTap: () => ref
                            .read(downloadsMapProvider.notifier)
                            .reorder(
                                downloadUpdate.chapter.id, downloadsCount - 1),
                      ),
                  ],
                ),
                ReorderableDragStartListener(
                  index: index,
                  child: Icon(
                    Icons.drag_handle_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            onTap: () =>
                MangaRoute(mangaId: downloadUpdate.manga.id).push(context),
          ),
          if (isDownloading)
            Padding(
              padding: const EdgeInsets.only(left: 72, right: 16),
              child: LinearProgressIndicator(
                minHeight: 2,
                value: downloadUpdate.progress,
              ),
            ),
        ],
      ),
    );
  }
}
