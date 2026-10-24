// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../graphql/__generated__/schema.graphql.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/misc/toast/toast.dart';
import '../../../utils/theme/brand.dart';
import '../../../widgets/custom_circular_progress_indicator.dart';
import '../../../widgets/popup_widgets/confirm_action.dart';
import '../../account/data/account_providers.dart';
import '../../auth/data/auth_credentials_store.dart';
import '../../offline/data/offline_download_providers.dart';
import '../data/downloads/downloads_repository.dart';
import '../data/manga_book/manga_book_repository.dart';
import '../domain/chapter/chapter_model.dart';
import '../domain/downloads/downloads_model.dart';
import '../presentation/downloads/controller/downloads_controller.dart';
import '../presentation/manga_details/controller/scanlator_propagation.dart';

class DownloadStatusIcon extends HookConsumerWidget {
  const DownloadStatusIcon({
    super.key,
    required this.updateData,
    required this.chapter,
    required this.mangaId,
    required this.isDownloaded,
  });
  final AsyncCallback updateData;
  final ChapterDto chapter;
  final int mangaId;
  final bool isDownloaded;

  Future<void> newUpdatePair(
    WidgetRef ref,
    ValueSetter<bool> setIsLoading,
  ) async {
    if (!ref.context.mounted) return;
    final current = ref
        .read(authCredentialsStoreProvider.notifier)
        .captureSession();
    if (!current()) return;
    try {
      setIsLoading(true);
      await updateData();
    } catch (_) {
    } finally {
      if (ref.context.mounted && current()) setIsLoading(false);
    }
  }

  Future<bool> toggleChapterToQueue(
    Toast? toast,
    WidgetRef ref, {
    bool isAdd = false,
    bool isRemove = false,
    bool isError = false,
  }) async {
    try {
      final current = ref
          .read(authCredentialsStoreProvider.notifier)
          .captureSession();
      final result = await AsyncValue.guard(() async {
        final repo = ref.read(downloadsRepositoryProvider);
        if (isRemove || isError) {
          await repo.removeChapterFromDownloadQueue(chapter.id);
          if (!current()) return;
        }
        if (isAdd || isError) {
          await repo.addChaptersBatchToDownloadQueue([chapter.id]);
          if (!ref.context.mounted || !current()) return;
          await updateData();
        }
      });
      result.showToastOnError(toast);
      return !result.hasError;
    } catch (e) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canDownload = ref
        .watch(settledAccountAccessProvider)
        .allows(Enum$UserPermission.DOWNLOAD_CHAPTERS);
    final isLoading = useState(false);
    final isEnqueuing = useState(false);

    final toast = ref.watch(toastProvider);
    final downloadUpdate = ref.watch(downloadsFromIdProvider(chapter.id));
    ref.listen(downloadUpdatesProvider, (_, next) {
      final finished =
          next.value?.updates.any(
            (update) =>
                update.type == DownloadUpdateType.FINISHED &&
                update.download.chapter.id == chapter.id,
          ) ??
          false;
      if (!finished) return;
      final current = ref
          .read(authCredentialsStoreProvider.notifier)
          .captureSession();
      Future.microtask(() async {
        if (!ref.context.mounted || !current()) return;
        await newUpdatePair(ref, (value) => isLoading.value = value);
      });
    });
    useEffect(() {
      if (downloadUpdate != null) {
        Future.microtask(() {
          if (context.mounted) isEnqueuing.value = false;
        });
      }
      return;
    }, [downloadUpdate != null]);

    if (isLoading.value) {
      final box = resolveIconButtonBox(context);
      return SizedBox(
        width: box.width,
        height: box.height,
        child: Center(
        child: MiniCircularProgressIndicator(color: context.iconColor),
        ),
      );
    } else {
      if (downloadUpdate != null) {
        if (downloadUpdate.state == DownloadState.ERROR) {
          return IconButton(
            tooltip: canDownload ? null : context.l10n.accountPermissionDenied,
            onPressed: !canDownload
                ? null
                : () => toggleChapterToQueue(toast, ref, isError: true),
            icon: const Icon(FluentIcons.replay_24_regular),
          );
        } else if (downloadUpdate.state == DownloadState.QUEUED) {
          // Use a determinate ring for queued chapters to avoid per-frame animation on every visible row.
          return IconButton(
            tooltip: canDownload ? null : context.l10n.accountPermissionDenied,
            onPressed: !canDownload
                ? null
                : () => toggleChapterToQueue(toast, ref, isRemove: true),
            icon: downloadUpdate.progress > 0
                ? MiniCircularProgressIndicator(
                    value: downloadUpdate.progress,
                    color: context.iconColor,
                  )
                : Icon(FluentIcons.clock_24_regular, color: context.iconColor),
          );
        } else {
          return IconButton(
            tooltip: canDownload ? null : context.l10n.accountPermissionDenied,
            onPressed: !canDownload
                ? null
                : () => toggleChapterToQueue(toast, ref, isRemove: true),
            icon: MiniCircularProgressIndicator(
              value: downloadUpdate.progress == 0
                  ? null
                  : downloadUpdate.progress,
              color: context.iconColor,
            ),
          );
        }
      } else {
        if (isDownloaded) {
          return IconButton(
            icon: brandGradientIcon(context, FluentIcons.cloud_checkmark_24_filled),
            onPressed: () async {
              if (!await confirmAction(
                    context,
                    title: context.l10n.deleteServerDownloads,
                    message: context.l10n.confirmDeleteBothDownloadsMessage,
                    action: context.l10n.delete,
                  ) ||
                  !context.mounted) {
                return;
              }
              // Capture the container before awaiting deletion; the chapter row and its ref may disappear.
              final containerRead = ProviderScope.containerOf(
                context,
                listen: false,
              ).read;
              final deleteIds = expandIdsAcrossScanlators(
                ref,
                mangaId: chapter.mangaId,
                chapterIds: [chapter.id],
              );
              final result = await AsyncValue.guard(
                () => ref
                    .read(mangaBookRepositoryProvider)
                    .deleteChapters(deleteIds),
              );
              result.showToastOnError(toast);
              if (!result.hasError) {
                await cascadeServerDeleteToDevice(containerRead, deleteIds);
              }
              await newUpdatePair(ref, (value) => isLoading.value = value);
            },
          );
        } else {
          if (isEnqueuing.value) {
            return IconButton(
              onPressed: null,
              icon: MiniCircularProgressIndicator(color: context.iconColor),
            );
          }
          return IconButton(
            icon: Icon(
              FluentIcons.cloud_arrow_down_24_regular,
              color: context.theme.colorScheme.onSurfaceVariant,
            ),
            tooltip: canDownload ? null : context.l10n.accountPermissionDenied,
            onPressed: !canDownload
                ? null
                : () async {
                    isEnqueuing.value = true;
                    // Wait for the queue feed, bounded to handle a disconnected feed or a skipped chapter.
                    if (await toggleChapterToQueue(toast, ref, isAdd: true)) {
                      await Future.delayed(const Duration(seconds: 10));
                    }
                    if (context.mounted) isEnqueuing.value = false;
                  },
          );
        }
      }
    }
  }
}
