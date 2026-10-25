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
import '../../../domain/chapter/chapter_model.dart';
import '../../../widgets/chapter_actions/chapter_bulk_actions.dart';
import 'chapter_context_menu.dart';

class ChapterSelectionHeader extends ConsumerWidget {
  const ChapterSelectionHeader({
    super.key,
    required this.selected,
    required this.ordered,
    required this.bulk,
    required this.anchorId,
    required this.desktop,
    required this.seriesUrl,
    required this.moreButtonKey,
    required this.onClear,
    required this.onSelectAll,
    required this.refresh,
    required this.onSelect,
    this.loadSeriesChapters,
  });
  final List<ChapterDto> selected;
  final List<ChapterDto> ordered;
  final List<ChapterDto> bulk;
  final int? anchorId;
  final bool desktop;
  final String? seriesUrl;
  final GlobalKey moreButtonKey;
  final VoidCallback onClear;
  final VoidCallback onSelectAll;
  final AsyncValueSetter<bool> refresh;
  final void Function(Map<int, ChapterDto> next, int anchorId) onSelect;
  final Future<List<ChapterDto>?> Function(int mangaId)? loadSeriesChapters;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = context.theme.colorScheme;
    final allRead =
        selected.isNotEmpty && selected.every((c) => c.user.isRead.ifNull());
    final allBookmarked =
        selected.isNotEmpty &&
        selected.every((c) => c.user.isBookmarked.ifNull());
    final anchor =
        selected.where((c) => c.id == anchorId).firstOrNull ?? selected.last;

    List<_HeaderAction> actions() => [
      _HeaderAction(
        icon: allRead ? Icons.remove_done_rounded : Icons.done_all_rounded,
        label: allRead ? context.l10n.markAsUnread : context.l10n.markAsRead,
        onTap: () => markChaptersRead(
          context: context,
          ref: ref,
          chapters: selected,
          isRead: !allRead,
          refresh: refresh,
        ),
      ),
      _HeaderAction(
        icon: allBookmarked
            ? FluentIcons.bookmark_24_filled
            : FluentIcons.bookmark_24_regular,
        label: allBookmarked
            ? context.l10n.removeBookmark
            : context.l10n.bookmark,
        onTap: () => setChaptersBookmark(
          ref: ref,
          chapters: selected,
          isBookmarked: !allBookmarked,
          refresh: refresh,
        ),
      ),
      _HeaderAction(
        icon: FluentIcons.arrow_circle_down_24_regular,
        label: context.l10n.keepOffline,
        onTap: () => keepChaptersOffline(
          context: context,
          ref: ref,
          chapters: selected,
          refresh: refresh,
        ),
      ),
      _HeaderAction(
        icon: FluentIcons.cloud_arrow_down_24_regular,
        label: context.l10n.download,
        onTap: () => queueServerDownload(
          context: context,
          ref: ref,
          chapterIds: [for (final c in selected) c.id],
          refresh: refresh,
        ),
      ),
    ];

    Future<void> markPrevious() async {
      final loader = loadSeriesChapters;
      if (loader == null) {
        await markPreviousAsRead(
          context: context,
          ref: ref,
          bulkList: bulk,
          anchor: anchor,
          refresh: refresh,
        );
        return;
      }
      final newestPerSeries = <int, ChapterDto>{};
      for (final c in selected) {
        final current = newestPerSeries[c.mangaId];
        if (current == null || c.index > current.index) {
          newestPerSeries[c.mangaId] = c;
        }
      }
      final previous = <ChapterDto>[];
      for (final entry in newestPerSeries.entries) {
        List<ChapterDto>? series;
        try {
          series = await loader(entry.key);
        } catch (_) {
          series = null;
        }
        if (!context.mounted) return;
        if (series == null) {
          ref
              .read(toastProvider)
              ?.showError(context.l10n.errorSomethingWentWrong);
          return;
        }
        previous.addAll(previousChapters(series, entry.value));
      }
      if (previous.isEmpty) return;
      await markChaptersRead(
        context: context,
        ref: ref,
        chapters: previous,
        isRead: true,
        refresh: refresh,
      );
    }

    Future<void> openMore(List<_HeaderAction> overflowed) async {
      final box =
          moreButtonKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) return;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      final anchorIndex = ordered.indexWhere((c) => c.id == anchor.id);
      final browserChapter = chapterHasBrowserTarget(anchor, seriesUrl)
          ? anchor
          : selected
                .where((c) => chapterHasBrowserTarget(c, seriesUrl))
                .firstOrNull;
      await showMenu<void>(
        context: context,
        position: menuAnchorForRect(
          context,
          Rect.fromLTWH(rect.left, rect.top, 0, 0),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        items: [
          for (final action in overflowed)
            PopupMenuItem(
              onTap: action.onTap,
              child: ChapterMenuRow(icon: action.icon, label: action.label),
            ),
          if (overflowed.isNotEmpty) const PopupMenuDivider(),
          PopupMenuItem(
            enabled:
                loadSeriesChapters != null ||
                previousChapters(bulk, anchor).isNotEmpty,
            onTap: markPrevious,
            child: ChapterMenuRow(
              icon: FluentIcons.text_bullet_list_checkmark_20_regular,
              label: context.l10n.markPreviousAsRead,
            ),
          ),
          const PopupMenuDivider(),
          PopupMenuItem(
            enabled: anchorIndex >= 0,
            onTap: () {
              if (anchorIndex < 0) return;
              onSelect({
                ...{for (final c in selected) c.id: c},
                for (final c in ordered.skip(anchorIndex + 1).take(10)) c.id: c,
              }, anchor.id);
            },
            child: ChapterMenuRow(
              icon: FluentIcons.task_list_ltr_24_regular,
              label: context.l10n.selectNext10,
            ),
          ),
          PopupMenuItem(
            enabled: anchorIndex >= 0,
            onTap: () {
              if (anchorIndex < 0) return;
              onSelect({
                ...{for (final c in selected) c.id: c},
                for (final c in ordered.skip(anchorIndex)) c.id: c,
              }, anchor.id);
            },
            child: ChapterMenuRow(
              icon: FluentIcons.arrow_down_24_regular,
              label: context.l10n.selectBelow,
            ),
          ),
          PopupMenuItem(
            onTap: () => onSelect({
              for (final c in ordered)
                if (!c.user.isRead.ifNull()) c.id: c,
            }, anchor.id),
            child: ChapterMenuRow(
              icon: FluentIcons.multiselect_ltr_24_regular,
              label: context.l10n.selectUnread,
            ),
          ),
          PopupMenuItem(
            onTap: () {
              final ids = {for (final c in selected) c.id};
              final first = ordered.indexWhere((c) => ids.contains(c.id));
              final last = ordered.lastIndexWhere((c) => ids.contains(c.id));
              if (first < 0 || last < 0) return;
              onSelect({
                for (var i = first; i <= last; i++) ordered[i].id: ordered[i],
              }, anchor.id);
            },
            child: ChapterMenuRow(
              icon: FluentIcons.arrow_autofit_height_24_regular,
              label: context.l10n.selectInBetween,
            ),
          ),
          if (browserChapter != null) const PopupMenuDivider(),
          if (browserChapter != null)
            PopupMenuItem(
              onTap: () =>
                  openChapterInBrowser(context, ref, browserChapter, seriesUrl),
              child: ChapterMenuRow(
                icon: FluentIcons.globe_24_regular,
                label: context.l10n.openInBrowser,
              ),
            ),
        ],
        popUpAnimationStyle: context.motionStyle,
      );
    }

    Future<void> deleteSelected() async {
      final deleted = await deleteChaptersFromServerWithConfirm(
        context: context,
        ref: ref,
        chapters: selected,
      );
      if (deleted) await refresh(true);
    }

    Widget moreButton(List<_HeaderAction> overflowed) => desktop
        ? TextButton.icon(
            key: moreButtonKey,
            onPressed: () => openMore(overflowed),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            icon: const Icon(FluentIcons.more_horizontal_24_regular, size: 24),
            label: Text(context.l10n.more),
          )
        : IconButton(
            key: moreButtonKey,
            tooltip: context.l10n.more,
            onPressed: () => openMore(overflowed),
            icon: const Icon(FluentIcons.more_horizontal_24_regular),
          );

    Widget actionButton(_HeaderAction action) => IconButton(
      tooltip: action.label,
      onPressed: action.onTap,
      style: desktop
          ? IconButton.styleFrom(
              minimumSize: const Size(40, 40),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            )
          : null,
      icon: Icon(action.icon),
    );

    return Padding(
      key: const ValueKey('chapterSelectionHeader'),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final all = actions();
          const closeWidth = 48.0;
          const selectAllWidth = 48.0;
          final actionWidth = desktop ? 40.0 : 48.0;
          const moreWidth = 108.0;
          const moreIconWidth = 48.0;
          const deleteFullWidth = 160.0;
          const deleteIconWidth = 40.0;
          final deleteLabelled =
              desktop &&
              constraints.maxWidth >=
                  closeWidth +
                      selectAllWidth +
                      all.length * actionWidth +
                      moreWidth +
                      deleteFullWidth;
          final deleteWidth = desktop
              ? (deleteLabelled ? deleteFullWidth : deleteIconWidth)
              : 48.0;
          final barWidth = desktop ? moreWidth : moreIconWidth;
          final visible =
              ((constraints.maxWidth -
                          (closeWidth +
                              selectAllWidth +
                              barWidth +
                              deleteWidth)) /
                      actionWidth)
                  .floor()
                  .clamp(0, all.length);
          final shown = all.take(visible).toList();
          final overflowed = all.skip(visible).toList();
          return Row(
            children: [
              IconButton(
                tooltip: context.l10n.cancel,
                icon: const Icon(FluentIcons.dismiss_24_regular),
                onPressed: onClear,
              ),
              Flexible(
                child: Text(
                  context.l10n.numSelected(selected.length),
                  style: context.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: context.l10n.selectAll,
                icon: const Icon(FluentIcons.select_all_on_24_regular),
                onPressed: onSelectAll,
              ),
              for (final action in shown) actionButton(action),
              moreButton(overflowed),
              if (deleteLabelled)
                TextButton.icon(
                  onPressed: deleteSelected,
                  icon: Icon(
                    FluentIcons.delete_24_regular,
                    color: cs.error,
                    size: 24,
                  ),
                  label: Text('${context.l10n.delete}…'),
                )
              else if (desktop)
                IconButton(
                  tooltip: context.l10n.delete,
                  onPressed: deleteSelected,
                  style: IconButton.styleFrom(
                    minimumSize: const Size(40, 40),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: Icon(FluentIcons.delete_24_regular, color: cs.error),
                )
              else
                IconButton(
                  tooltip: context.l10n.delete,
                  onPressed: deleteSelected,
                  icon: Icon(FluentIcons.delete_24_regular, color: cs.error),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _HeaderAction {
  const _HeaderAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}
