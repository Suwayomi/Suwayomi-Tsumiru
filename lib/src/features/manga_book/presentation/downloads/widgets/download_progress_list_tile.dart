// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../constants/app_sizes.dart';
import '../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../../../../../utils/motion/reduce_motion.dart';
import '../../../../../widgets/popup_widgets/confirm_action.dart';
import '../../../../../widgets/server_image.dart';
import '../../../../account/data/account_providers.dart';
import '../../../../auth/data/auth_credentials_store.dart';
import '../../../data/downloads/downloads_repository.dart';
import '../../../domain/downloads/downloads_model.dart';
import '../../manga_details/widgets/chapter_context_menu.dart';
import '../controller/downloads_controller.dart';

class DownloadProgressListTile extends HookConsumerWidget {
  const DownloadProgressListTile({
    super.key,
    required this.chapterId,
    required this.toast,
    required this.index,
    required this.downloadsCount,
    this.dragIndex,
    this.selecting = false,
    this.selected = false,
    this.onSelect,
    this.onTap,
  });
  final int chapterId;
  final Toast? toast;
  final int index;
  final int downloadsCount;
  final int? dragIndex;
  final bool selecting;
  final bool selected;
  final VoidCallback? onSelect;
  final VoidCallback? onTap;

  Future toggleChapterToQueue(
    Toast? toast,
    WidgetRef ref,
    bool addToDownload,
    int chapterId,
  ) async {
    try {
      (await AsyncValue.guard(() async {
        final current = ref
            .read(authCredentialsStoreProvider.notifier)
            .captureSession();
        final repo = ref.read(downloadsRepositoryProvider);
        await repo.removeChapterFromDownloadQueue(chapterId);
        if (!current()) return;
        if (addToDownload) {
          await repo.addChaptersBatchToDownloadQueue([chapterId]);
        }
      })).showToastOnError(toast);
      // ignore: empty_catches
    } catch (e) {}
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

  Future<void> confirmCancelSeries(
    BuildContext context,
    WidgetRef ref,
    List<int> chapterIds,
  ) async {
    if (chapterIds.length > 1) {
      if (!await confirmAction(
            context,
            title: context.l10n.cancelDownloadsTitle(chapterIds.length),
            message: context.l10n.cancelDownloadsMessage,
            action: context.l10n.cancelDownloads,
          ) ||
          !context.mounted) {
        return;
      }
    }
    await cancelQueued(context, ref, chapterIds);
  }

  Future<void> cancelQueued(
    BuildContext context,
    WidgetRef ref,
    List<int> chapterIds,
  ) async {
    final toast = ref.read(toastProvider);
    final stillRequested = context.l10n.stillRequestedByAnotherAccount;
    final result = await AsyncValue.guard(
      () =>
          ref.read(downloadsMapProvider.notifier).cancelQueuedChapters(chapterIds),
    );
    result.showToastOnError(toast);
    if ((result.asData?.value ?? const <int>{}).isNotEmpty) {
      toast?.show(stillRequested);
    }
  }

  String _stateText(BuildContext context, DownloadDto downloadUpdate) =>
      switch (downloadUpdate.state) {
        DownloadState.QUEUED => context.l10n.queued,
        DownloadState.DOWNLOADING => _downloadingText(context, downloadUpdate),
        DownloadState.ERROR => downloadUpdate.manga.source == null
            ? context.l10n.sourceRemoved
            : downloadUpdate.toDisplayName(context),
        DownloadState.FINISHED => downloadUpdate.toDisplayName(context),
        DownloadState.$unknown => throw UnimplementedError(),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canDownload = ref
        .watch(settledAccountAccessProvider)
        .allows(Enum$UserPermission.DOWNLOAD_CHAPTERS);
    final hovered = useState(false);
    final pointer = useRef(Offset.zero);
    final downloadUpdate = ref.watch(downloadsFromIdProvider(chapterId));
    if (downloadUpdate == null) return const SizedBox.shrink();
    final colorScheme = context.theme.colorScheme;
    final isError = downloadUpdate.state == DownloadState.ERROR;
    final isDownloading = downloadUpdate.state == DownloadState.DOWNLOADING;
    final desktop = context.usesDesktopShell;
    final drag = dragIndex ?? index;
    final cover = SizedBox(
      width: 40,
      height: 56,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: ServerImage(
          imageUrl: downloadUpdate.manga.thumbnailUrl ?? '',
          fit: BoxFit.cover,
        ),
      ),
    );
    List<PopupMenuEntry<void>> menuItems() {
      PopupMenuItem<void> item(
        String label,
        IconData icon,
        VoidCallback action, {
        bool enabled = true,
      }) => PopupMenuItem<void>(
        enabled: enabled,
        onTap: action,
        child: ChapterMenuRow(icon: icon, label: label),
      );
      DownloadsMap controller() => ref.read(downloadsMapProvider.notifier);
      return [
        item(context.l10n.select, Icons.check_box_outlined, onSelect ?? () {}),
        const PopupMenuDivider(),
        if (desktop || index > 0)
          item(
            context.l10n.moveToTop,
            FluentIcons.arrow_up_24_regular,
            () => controller().reorder(chapterId, 0),
            enabled: canDownload,
          ),
        if (desktop || index < downloadsCount - 1)
          item(
            context.l10n.moveToBottom,
            FluentIcons.arrow_down_24_regular,
            () => controller().reorder(chapterId, downloadsCount - 1),
            enabled: canDownload,
          ),
        item(
          context.l10n.moveSeriesToTop,
          FluentIcons.arrow_up_24_regular,
          () => controller().moveSeries(downloadUpdate.manga.id, toTop: true),
          enabled: canDownload,
        ),
        item(
          context.l10n.moveSeriesToBottom,
          FluentIcons.arrow_down_24_regular,
          () => controller().moveSeries(downloadUpdate.manga.id, toTop: false),
          enabled: canDownload,
        ),
        const PopupMenuDivider(),
        if (isError)
          item(
            context.l10n.retry,
            FluentIcons.replay_24_regular,
            () => toggleChapterToQueue(toast, ref, true, chapterId),
            enabled: canDownload,
          ),
        item(
          context.l10n.cancel,
          FluentIcons.dismiss_24_regular,
          () => cancelQueued(context, ref, [chapterId]),
          enabled: canDownload,
        ),
        item(
          context.l10n.cancelAllForThisSeries,
          FluentIcons.dismiss_circle_24_regular,
          () => confirmCancelSeries(context, ref, [
            for (final d in ref.read(downloadsMapProvider).values)
              if (d.manga.id == downloadUpdate.manga.id) d.chapter.id,
          ]),
          enabled: canDownload,
        ),
      ];
    }

    void openMenu(Offset point) => showMenu<void>(
      context: context,
      position: menuAnchorForPoint(context, point),
      items: menuItems(),
      shape: RoundedRectangleBorder(borderRadius: KBorderRadius.r16.radius),
      popUpAnimationStyle: context.motionStyle,
    );
    if (desktop) {
      return MouseRegion(
        onEnter: (_) => hovered.value = true,
        onExit: (_) => hovered.value = false,
        child: GestureDetector(
          onSecondaryTapDown: (event) => openMenu(event.globalPosition),
          child: Material(
            color: selected
                ? colorScheme.secondaryContainer
                : hovered.value
                ? colorScheme.surfaceContainerLow
                : colorScheme.surface.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap:
                  onTap ??
                  () => MangaRoute(
                    mangaId: downloadUpdate.manga.id,
                  ).push(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    if (selecting)
                      SizedBox(
                        width: 34,
                        child: Checkbox(
                          value: selected,
                          onChanged: (_) => onSelect?.call(),
                        ),
                      )
                    else
                      SizedBox(
                        width: 34,
                        child: hovered.value
                            ? ReorderableDragStartListener(
                                index: drag,
                                enabled: canDownload,
                                child: Icon(
                                  FluentIcons.re_order_24_regular,
                                  size: 20,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              )
                            : null,
                      ),
                    cover,
                    const SizedBox(width: 14),
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            downloadUpdate.manga.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.textTheme.titleSmall,
                          ),
                          Text(
                            downloadUpdate.chapter.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (isDownloading)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: SizedBox(
                                width: 220,
                                child: LinearProgressIndicator(
                                  minHeight: 4,
                                  value: downloadUpdate.progress,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: Text(
                        _stateText(context, downloadUpdate),
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.bodySmall?.copyWith(
                          color: isError
                              ? colorScheme.error
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      child: isError && hovered.value
                          ? IconButton(
                              tooltip: context.l10n.retry,
                              icon: const Icon(FluentIcons.replay_24_regular),
                              onPressed: canDownload
                                  ? () => toggleChapterToQueue(
                                      toast,
                                      ref,
                                      true,
                                      chapterId,
                                    )
                                  : null,
                            )
                          : null,
                    ),
                    SizedBox(
                      width: 40,
                      child: hovered.value
                          ? Listener(
                              onPointerDown: (event) =>
                                  pointer.value = event.position,
                              child: IconButton(
                                tooltip: context.l10n.more,
                                icon: const Icon(
                                  FluentIcons.more_vertical_24_regular,
                                ),
                                onPressed: () => openMenu(pointer.value),
                              ),
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return ReorderableDelayedDragStartListener(
      index: drag,
      enabled: canDownload && !selecting,
      child: Column(
        children: [
          ListTile(
            isThreeLine: true,
            selected: selected,
            leading: selecting
                ? Checkbox(value: selected, onChanged: (_) => onSelect?.call())
                : cover,
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
                  icon: const Icon(
                    FluentIcons.more_vertical_24_regular,
                  ),
                  enabled: canDownload,
                  tooltip: canDownload
                      ? null
                      : context.l10n.accountPermissionDenied,
                  shape: RoundedRectangleBorder(
                    borderRadius: KBorderRadius.r16.radius,
                  ),
                  itemBuilder: (context) => menuItems(),
                  popUpAnimationStyle: context.motionStyle,
                ),
                ReorderableDragStartListener(
                  index: drag,
                  enabled: canDownload && !selecting,
                  child: Icon(
                    FluentIcons.re_order_24_regular,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            onTap:
                onTap ??
                () =>
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
