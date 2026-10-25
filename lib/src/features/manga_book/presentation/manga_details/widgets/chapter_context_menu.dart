// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../../../../../utils/motion/reduce_motion.dart';
import '../../../../offline/data/offline_download_providers.dart';
import '../../../../offline/data/offline_repository.dart';
import '../../../../offline/data/offline_types.dart';
import '../../../../settings/presentation/koreader_sync/data/koreader_sync_repository.dart';
import '../../../domain/chapter/chapter_model.dart';
import '../../../domain/manga/manga_model.dart';
import '../../../widgets/chapter_actions/chapter_bulk_actions.dart';
import '../../reader/utils/koreader_progress_actions.dart';

RelativeRect menuAnchorForRect(BuildContext context, Rect rect) {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  return RelativeRect.fromRect(rect, Offset.zero & overlay.size);
}

RelativeRect menuAnchorForPoint(BuildContext context, Offset point) =>
    menuAnchorForRect(context, point & const Size(1, 1));

/// Shared ⋮/right-click menu; right-click never toggles selection.
Future<void> showChapterContextMenu({
  required BuildContext context,
  required WidgetRef ref,
  required RelativeRect position,
  required MangaDto manga,
  required ChapterDto chapter,
  required ValueNotifier<Map<int, ChapterDto>> selectedChapters,
  required ValueNotifier<int?> selectionAnchor,
  required List<ChapterDto> orderedChapters,
  required List<ChapterDto> bulkChapters,
  required AsyncCallback refresh,
  void Function()? refocus,
}) async {
  final connected = koSyncOnline(ref)
      ? await ref
            .read(koSyncStatusProvider.future)
            .then((status) => status.isLoggedIn)
            .catchError((_) => false)
      : false;
  if (!context.mounted) return;
  final selecting =
      selectedChapters.value.isNotEmpty &&
      selectedChapters.value.containsKey(chapter.id);
  final targets = selecting
      ? selectedChapters.value.values.toList()
      : [chapter];

  void replaceSelection(Map<int, ChapterDto> next, int anchorId) {
    selectedChapters.value = next;
    selectionAnchor.value = anchorId;
  }

  List<PopupMenuEntry<void>> buildSingleItems() {
    final read = chapter.user.isRead.ifNull();
    final bookmarked = chapter.user.isBookmarked.ifNull();
    final canDownload = canDownloadChapters(ref);
    final offlineEnabled = ref.read(offlineEnabledProvider);
    final onDevice =
        ref.read(offlineChapterStateProvider(chapter.id)).value ==
        OfflineDeviceState.downloaded;
    final index = orderedChapters.indexWhere((c) => c.id == chapter.id);
    final items = <PopupMenuEntry<void>>[
      PopupMenuItem(
        onTap: () {
          toggleChapterBookmark(ref, chapter);
          refresh();
        },
        child: ChapterMenuRow(
          icon: bookmarked
              ? FluentIcons.bookmark_24_filled
              : FluentIcons.bookmark_24_regular,
          label: bookmarked
              ? context.l10n.removeBookmark
              : context.l10n.bookmark,
        ),
      ),
      PopupMenuItem(
        onTap: () => markChaptersRead(
          context: context,
          ref: ref,
          chapters: [chapter],
          isRead: !read,
          refresh: (_) => refresh(),
        ),
        child: ChapterMenuRow(
          icon: Icons.done_rounded,
          label: read ? context.l10n.markAsUnread : context.l10n.markAsRead,
        ),
      ),
      if (connected)
        for (final push in [true, false])
          PopupMenuItem(
            enabled: koSyncOnline(ref),
            onTap: () async {
              await syncKoReaderChapter(
                context: context,
                ref: ref,
                chapter: chapter,
                push: push,
              );
              await refresh();
            },
            child: ChapterMenuRow(
              icon: push
                  ? FluentIcons.cloud_arrow_up_24_regular
                  : FluentIcons.cloud_arrow_down_24_regular,
              label: push
                  ? context.l10n.pushKoReaderProgress
                  : context.l10n.pullKoReaderProgress,
        ),
      ),
      const PopupMenuDivider(),
      PopupMenuItem(
        enabled: previousChapters(bulkChapters, chapter).isNotEmpty,
        onTap: () => markPreviousAsRead(
          context: context,
          ref: ref,
          bulkList: bulkChapters,
          anchor: chapter,
          refresh: (_) => refresh(),
        ),
        child: ChapterMenuRow(
          icon: FluentIcons.text_bullet_list_checkmark_20_regular,
          label: context.l10n.markPreviousAsRead,
        ),
      ),
      PopupMenuItem(
        onTap: () => replaceSelection({chapter.id: chapter}, chapter.id),
        child: ChapterMenuRow(
          icon: FluentIcons.checkbox_unchecked_24_regular,
          label: context.l10n.select,
        ),
      ),
      PopupMenuItem(
        onTap: () {
          if (index < 0) return;
          final next = {
            ...selectedChapters.value,
            for (final c in orderedChapters.skip(index + 1).take(10)) c.id: c,
          };
          replaceSelection(next, chapter.id);
        },
        child: ChapterMenuRow(
          icon: FluentIcons.task_list_ltr_24_regular,
          label: context.l10n.selectNext10,
        ),
      ),
      PopupMenuItem(
        onTap: () {
          if (index < 0) return;
          final next = {
            ...selectedChapters.value,
            for (final c in orderedChapters.skip(index)) c.id: c,
          };
          replaceSelection(next, chapter.id);
        },
        child: ChapterMenuRow(
          icon: FluentIcons.arrow_down_24_regular,
          label: context.l10n.selectBelow,
        ),
      ),
      PopupMenuItem(
        onTap: () => replaceSelection({
          for (final c in orderedChapters)
            if (!c.user.isRead.ifNull()) c.id: c,
        }, chapter.id),
        child: ChapterMenuRow(
          icon: FluentIcons.multiselect_ltr_24_regular,
          label: context.l10n.selectUnread,
        ),
      ),
      PopupMenuItem(
        onTap: () => replaceSelection({
          for (final c in orderedChapters) c.id: c,
        }, chapter.id),
        child: ChapterMenuRow(
          icon: FluentIcons.select_all_on_24_regular,
          label: context.l10n.selectAll,
        ),
      ),
      if (selectedChapters.value.isNotEmpty)
        PopupMenuItem(
          onTap: () {
            final ids = selectedChapters.value.keys.toSet();
            final firstSelected = orderedChapters.indexWhere(
              (c) => ids.contains(c.id),
            );
            final lastSelected = orderedChapters.lastIndexWhere(
              (c) => ids.contains(c.id),
            );
            if (firstSelected < 0 || lastSelected < 0) return;
            replaceSelection({
              for (var i = firstSelected; i <= lastSelected; i++)
                orderedChapters[i].id: orderedChapters[i],
            }, chapter.id);
          },
          child: ChapterMenuRow(
            icon: FluentIcons.arrow_autofit_height_24_regular,
            label: context.l10n.selectInBetween,
          ),
        ),
      const PopupMenuDivider(),
      if (chapterHasBrowserTarget(chapter, manga.realUrl))
        PopupMenuItem(
          onTap: () =>
              openChapterInBrowser(context, ref, chapter, manga.realUrl),
          child: ChapterMenuRow(
            icon: FluentIcons.globe_24_regular,
            label: context.l10n.openInBrowser,
          ),
        ),
      if (chapterHasBrowserTarget(chapter, manga.realUrl))
        const PopupMenuDivider(),
      if (offlineEnabled)
        PopupMenuItem(
          enabled: !onDevice || canDownload,
          onTap: () async {
            if (onDevice) {
              await removeChapterFromDevice(ref, chapter.id);
            } else {
              try {
                await keepChapterOffline(ref, chapter.id);
              } catch (_) {
                if (context.mounted) {
                  ref
                      .read(toastProvider)
                      ?.showError(context.l10n.errorSomethingWentWrong);
                }
              }
            }
            await refresh();
          },
          child: ChapterMenuRow(
            icon: onDevice ? FluentIcons.checkmark_circle_24_filled : FluentIcons.arrow_circle_down_24_regular,
            label: onDevice
                ? context.l10n.removeFromDevice
                : context.l10n.keepOffline,
          ),
        ),
      if (chapter.user.isDownloaded.ifNull())
        _DangerMenuItem(
          icon: FluentIcons.delete_24_regular,
          label: context.l10n.deleteFromServer,
          onTap: () async {
            final deleted = await deleteChaptersFromServerWithConfirm(
              context: context,
              ref: ref,
              chapters: [chapter],
            );
            if (deleted) await refresh();
          },
        )
      else
        PopupMenuItem(
          enabled: canDownload,
          onTap: () => queueServerDownload(
            context: context,
            ref: ref,
            chapterIds: [chapter.id],
            refresh: (_) => refresh(),
          ),
          child: ChapterMenuRow(
            icon: FluentIcons.cloud_arrow_down_24_regular,
            label: context.l10n.download,
          ),
        ),
    ];
    return items;
  }

  List<PopupMenuEntry<void>> buildSelectionItems() {
    final allRead = targets.every((c) => c.user.isRead.ifNull());
    final allBookmarked = targets.every((c) => c.user.isBookmarked.ifNull());
    final canDownload = canDownloadChapters(ref);
    return [
      PopupMenuItem(
        enabled: false,
        child: Text(
          context.l10n.numSelected(targets.length),
          style: context.textTheme.labelLarge,
        ),
      ),
      const PopupMenuDivider(),
      PopupMenuItem(
        onTap: () => setChaptersBookmark(
          ref: ref,
          chapters: targets,
          isBookmarked: !allBookmarked,
          refresh: (_) => refresh(),
        ),
        child: ChapterMenuRow(
          icon: allBookmarked
              ? FluentIcons.bookmark_24_filled
              : FluentIcons.bookmark_24_regular,
          label: allBookmarked
              ? context.l10n.removeBookmark
              : context.l10n.bookmark,
        ),
      ),
      PopupMenuItem(
        onTap: () => markChaptersRead(
          context: context,
          ref: ref,
          chapters: targets,
          isRead: !allRead,
          refresh: (_) => refresh(),
        ),
        child: ChapterMenuRow(
          icon: Icons.done_rounded,
          label: allRead ? context.l10n.markAsUnread : context.l10n.markAsRead,
        ),
      ),
      const PopupMenuDivider(),
      PopupMenuItem(
        enabled: canDownload,
        onTap: () => keepChaptersOffline(
          context: context,
          ref: ref,
          chapters: targets,
          refresh: (_) => refresh(),
        ),
        child: ChapterMenuRow(
          icon: FluentIcons.arrow_circle_down_24_regular,
          label: context.l10n.keepOffline,
        ),
      ),
      PopupMenuItem(
        enabled: canDownload,
        onTap: () => queueServerDownload(
          context: context,
          ref: ref,
          chapterIds: [for (final c in targets) c.id],
          refresh: (_) => refresh(),
        ),
        child: ChapterMenuRow(
          icon: FluentIcons.cloud_arrow_down_24_regular,
          label: context.l10n.download,
        ),
      ),
      const PopupMenuDivider(),
      _DangerMenuItem(
        icon: FluentIcons.delete_24_regular,
        label: context.l10n.deleteFromServer,
        onTap: () async {
          final deleted = await deleteChaptersFromServerWithConfirm(
            context: context,
            ref: ref,
            chapters: targets,
          );
          if (deleted) await refresh();
        },
      ),
    ];
  }

  await showMenu<void>(
    context: context,
    position: position,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    items: selecting ? buildSelectionItems() : buildSingleItems(),
    popUpAnimationStyle: context.motionStyle,
  );
  refocus?.call();
}

class ChapterMenuRow extends StatelessWidget {
  const ChapterMenuRow({super.key, required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) {
    final muted = context.theme.colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(icon, size: 20, color: muted),
        const SizedBox(width: 12),
        Flexible(child: Text(label)),
      ],
    );
  }
}

/// Danger icon, normal-ink label: error text misses contrast on dark themes.
class _DangerMenuItem extends PopupMenuEntry<void> {
  const _DangerMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final AsyncCallback onTap;
  @override
  double get height => kMinInteractiveDimension;
  @override
  bool represents(void value) => false;
  @override
  State<StatefulWidget> createState() => _DangerMenuItemState();
}

class _DangerMenuItemState extends State<_DangerMenuItem> {
  void _handleTap() {
    Navigator.pop(context);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.theme.colorScheme;
    return InkWell(
      onTap: _handleTap,
      canRequestFocus: true,
      hoverColor: cs.error.withValues(alpha: 0.12),
      highlightColor: cs.error.withValues(alpha: 0.18),
      child: SizedBox(
        height: widget.height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(widget.icon, size: 20, color: cs.error),
              const SizedBox(width: 12),
              Flexible(child: Text(widget.label)),
            ],
          ),
        ),
      ),
    );
  }
}
