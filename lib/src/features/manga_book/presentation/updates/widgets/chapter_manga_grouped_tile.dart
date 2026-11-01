// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math' as math;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../constants/app_sizes.dart';
import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/motion/reduce_motion.dart';
import '../../../../../widgets/desktop/desktop_exact_extent_list.dart';
import '../../../../../widgets/desktop/desktop_page_frame.dart';
import '../../../../../widgets/hover_tap_target.dart';
import '../../../../../widgets/server_image.dart';
import '../../../../../widgets/web_route_link.dart';
import '../../../domain/chapter/chapter_model.dart';
import '../../../domain/manga/manga_model.dart';
import '../../../widgets/download_status_icon.dart';
import '../../manga_details/widgets/chapter_context_menu.dart';
import '../controller/updates_grouping_controller.dart';
import 'updates_row_actions.dart';

double desktopUpdatesRowExtent(
  BuildContext context,
  ChapterWithMangaDto chapter,
  double width, {
  required bool selecting,
  int tailCount = 0,
  bool tail = false,
}) {
  final padding = (tail
      ? const EdgeInsets.fromLTRB(16, 6, 16, 6)
      : const EdgeInsets.symmetric(horizontal: 16, vertical: 8))
      .onDesktopPageLine(context);
  final hasCover = chapter.manga.displayCoverUrl.isNotEmpty;
  final bookmark = chapter.user.isBookmarked ? 24.0 : 0.0;
  final textWidth = width - padding.horizontal -
      (selecting ? 48 : 0) - (tail ? 68 : (hasCover ? 56 : 0) + 12) -
      8 - (tail ? 0 : 84) - (selecting ? 0 : 64) - 48;
  if (tail) {
    return padding.vertical + math.max(48, desktopTextHeight(
      context, chapter.name, const TextStyle(fontSize: 13),
      width: textWidth - bookmark,
    ));
  }
  final title = desktopTextHeight(
    context, chapter.manga.title, null,
    width: textWidth - bookmark, maxLines: 2,
  );
  final titleHeight = bookmark > 0 ? math.max(20.0, title) : title;
  final chapterHeight = desktopTextHeight(
    context, chapter.name, null, width: textWidth,
  );
  final labelHeight = tailCount > 0
      ? 2 + math.max(14, desktopTextHeight(
          context, context.l10n.updatesGroupingShowMore(tailCount),
          context.textTheme.labelSmall, width: textWidth - 16,
        ))
      : 0.0;
  return padding.vertical + math.max(
    hasCover ? 80 : 48, titleHeight + 4 + chapterHeight + labelHeight,
  );
}

/// An empty [tail] behaves like ChapterMangaListTile.
class ChapterMangaGroupedTile extends HookConsumerWidget {
  const ChapterMangaGroupedTile({
    super.key,
    required this.head,
    required this.tail,
    required this.updatePairFor,
    required this.refreshManga,
    required this.refreshRowActions,
    required this.isSelectedFor,
    required this.toggleSelect,
    required this.selectedChapters,
    required this.selectionAnchor,
    required this.orderedChapters,
    required this.canTapSelect,
    required this.desktop,
    this.desktopExpanded,
    this.onDesktopToggleExpand,
    this.desktopTailIndex,
  });

  final ChapterWithMangaDto head;

  /// Additional chapters for this manga on the same day (already sorted).
  final List<ChapterWithMangaDto> tail;

  final Future<void> Function() Function(ChapterWithMangaDto) updatePairFor;

  final Future<void> Function() refreshManga;
  final Future<void> Function(Set<int> mangaIds) refreshRowActions;

  /// Selection is per chapter: head and tail rows can be selected independently.
  final bool Function(ChapterWithMangaDto) isSelectedFor;
  final ValueChanged<ChapterWithMangaDto> toggleSelect;
  final ValueNotifier<Map<int, ChapterDto>> selectedChapters;
  final ValueNotifier<int?> selectionAnchor;
  final List<ChapterDto> orderedChapters;
  final bool canTapSelect;
  final bool desktop;
  final bool? desktopExpanded;
  final VoidCallback? onDesktopToggleExpand;
  final int? desktopTailIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (desktopTailIndex != null) {
      final chapter = tail[desktopTailIndex!];
      return _TailTile(
        chapter: chapter,
        updatePair: updatePairFor(chapter),
        refreshManga: refreshManga,
        refreshRowActions: refreshRowActions,
        isSelected: isSelectedFor(chapter),
        canTapSelect: canTapSelect,
        toggleSelect: toggleSelect,
        selectedChapters: selectedChapters,
        selectionAnchor: selectionAnchor,
        orderedChapters: orderedChapters,
        desktop: desktop,
      );
    }
    if (desktopExpanded != null) {
      return _HeadTile(
        chapter: head,
        isGroup: tail.isNotEmpty,
        tailCount: tail.length,
        isExpanded: desktopExpanded!,
        onToggleExpand: onDesktopToggleExpand,
        updatePair: updatePairFor(head),
        refreshManga: refreshManga,
        refreshRowActions: refreshRowActions,
        isSelected: isSelectedFor(head),
        canTapSelect: canTapSelect,
        toggleSelect: toggleSelect,
        selectedChapters: selectedChapters,
        selectionAnchor: selectionAnchor,
        orderedChapters: orderedChapters,
        desktop: desktop,
      );
    }
    final groupingMode =
        ref.watch(updatesGroupingModeProvider) ?? UpdatesGroupingMode.collapsed;

    final isExpanded = useState(groupingMode == UpdatesGroupingMode.expanded);
    useEffect(() {
      isExpanded.value = groupingMode == UpdatesGroupingMode.expanded;
      return null;
    }, [groupingMode]);

    final isGroup = tail.isNotEmpty;
    final tailTiles = isExpanded.value
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final chapter in tail)
                _TailTile(
                  chapter: chapter,
                  updatePair: updatePairFor(chapter),
                  refreshManga: refreshManga,
                  refreshRowActions: refreshRowActions,
                  isSelected: isSelectedFor(chapter),
                  canTapSelect: canTapSelect,
                  toggleSelect: toggleSelect,
                  selectedChapters: selectedChapters,
                  selectionAnchor: selectionAnchor,
                  orderedChapters: orderedChapters,
                  desktop: desktop,
                ),
            ],
          )
        : const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _HeadTile(
          chapter: head,
          isGroup: isGroup,
          tailCount: tail.length,
          isExpanded: isExpanded.value,
          onToggleExpand: isGroup
              ? () => isExpanded.value = !isExpanded.value
              : null,
          updatePair: updatePairFor(head),
          refreshManga: refreshManga,
          refreshRowActions: refreshRowActions,
          isSelected: isSelectedFor(head),
          canTapSelect: canTapSelect,
          toggleSelect: toggleSelect,
          selectedChapters: selectedChapters,
          selectionAnchor: selectionAnchor,
          orderedChapters: orderedChapters,
          desktop: desktop,
        ),
        if (isGroup)
          context.reduceMotion
              ? tailTiles
              : AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
                  child: tailTiles,
                ),
      ],
    );
  }
}

class _HeadTile extends HookConsumerWidget {
  const _HeadTile({
    required this.chapter,
    required this.isGroup,
    required this.tailCount,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.updatePair,
    required this.refreshManga,
    required this.refreshRowActions,
    required this.isSelected,
    required this.canTapSelect,
    required this.toggleSelect,
    required this.selectedChapters,
    required this.selectionAnchor,
    required this.orderedChapters,
    required this.desktop,
  });

  final ChapterWithMangaDto chapter;
  final bool isGroup;
  final int tailCount;
  final bool isExpanded;
  final VoidCallback? onToggleExpand;
  final Future<void> Function() updatePair;
  final Future<void> Function() refreshManga;
  final Future<void> Function(Set<int> mangaIds) refreshRowActions;
  final bool isSelected;
  final bool canTapSelect;
  final ValueChanged<ChapterWithMangaDto> toggleSelect;
  final ValueNotifier<Map<int, ChapterDto>> selectedChapters;
  final ValueNotifier<int?> selectionAnchor;
  final List<ChapterDto> orderedChapters;
  final bool desktop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hovered = useState(false);
    final color = (chapter.user.isRead).ifNull()
        ? context.theme.colorScheme.onSurface.withValues(alpha: 0.38)
        : null;
    final manga = chapter.manga;

    void openMenuAt(Offset position) {
      showUpdatesChapterMenu(
        context: context,
        ref: ref,
        position: menuAnchorForPoint(context, position),
        chapter: chapter,
        seriesUrl: manga.realUrl,
        selectedChapters: selectedChapters,
        selectionAnchor: selectionAnchor,
        orderedChapters: orderedChapters,
        refreshSeries: refreshRowActions,
      );
    }

    return Material(
      color: isSelected
          ? desktop
                ? context.theme.colorScheme.primary.withValues(alpha: 0.16)
                : context.theme.colorScheme.secondaryContainer
          : Colors.transparent,
      child: WebRouteLink(
        location: ReaderRoute(
          mangaId: manga.id,
          chapterId: chapter.id,
          showReaderLayoutAnimation: true,
        ).location,
        builder: (context, openInNewTab) => GestureDetector(
          onSecondaryTapDown: desktop
              ? (details) => openMenuAt(details.globalPosition)
              : null,
          child: MouseRegion(
            onEnter: (_) => hovered.value = true,
            onExit: (_) => hovered.value = false,
            child: InkWell(
              onTap: () => WebRouteLink.handleAsyncTap(openInNewTab, () async {
                if (canTapSelect) {
                  toggleSelect(chapter);
                } else {
                  await ReaderRoute(
                    mangaId: manga.id,
                    chapterId: chapter.id,
                    showReaderLayoutAnimation: true,
                  ).push(context);
                  if (!context.mounted) return;
                  await refreshManga();
                }
              }),
              onLongPress: () => toggleSelect(chapter),
              onSecondaryTap: desktop ? null : () => toggleSelect(chapter),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ).onDesktopPageLine(context),
                child: Row(
                  children: [
                    if (desktop && canTapSelect)
                      Checkbox(
                        value: isSelected,
                        visualDensity: VisualDensity.compact,
                        onChanged: (_) => toggleSelect(chapter),
                      ),
                    if (manga.displayCoverUrl.isNotEmpty)
                      ClipRRect(
                        borderRadius: KBorderRadius.r8.radius,
                        child: WebRouteLink(
                          location: MangaRoute(mangaId: manga.id).location,
                          enabled: false,
                          builder: (context, openMangaInNewTab) => InkWell(
                            onTap: () => WebRouteLink.handleAsyncTap(
                              openMangaInNewTab,
                              () async {
                                if (canTapSelect) {
                                  toggleSelect(chapter);
                                  return;
                                }
                                await MangaRoute(
                                  mangaId: manga.id,
                                ).push(context);
                                if (!context.mounted) return;
                                await refreshManga();
                              },
                            ),
                            child: ServerImage(
                              imageUrl: manga.displayCoverUrl,
                              fallbackImageUrl: manga.thumbnailUrl,
                              coverVersion: manga.coverVersion,
                              fallbackCoverVersion:
                                  manga.thumbnailUrlLastFetched,
                              size: const Size(56, 80),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              if ((chapter.user.isBookmarked).ifNull()) ...[
                                const Icon(
                                  FluentIcons.bookmark_24_filled,
                                  size: 20,
                                ),
                                const SizedBox(width: 4),
                              ],
                              Expanded(
                                child: Text(
                                  manga.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: color),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            chapter.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color:
                                  color ??
                                  context.theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (isGroup)
                            HoverTapTarget(
                              builder: (context, hovered) => GestureDetector(
                                onTap: onToggleExpand,
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        context.l10n.updatesGroupingShowMore(
                                          tailCount,
                                        ),
                                        style: context.textTheme.labelSmall
                                            ?.copyWith(
                                              color: context
                                                  .theme
                                                  .colorScheme
                                                  .primary,
                                              decoration: hovered
                                                  ? TextDecoration.underline
                                                  : TextDecoration.none,
                                            ),
                                      ),
                                      const SizedBox(width: 2),
                                      Icon(
                                        isExpanded
                                            ? FluentIcons.chevron_up_24_regular
                                            : FluentIcons
                                                  .chevron_down_24_regular,
                                        size: 14,
                                        color:
                                            context.theme.colorScheme.primary,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (desktop)
                      SizedBox(
                        width: 84,
                        child: Text(
                          int.tryParse(
                            chapter.fetchedAt,
                          ).toShortTimeFromSeconds(context),
                          textAlign: TextAlign.right,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: context.theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    if (desktop && !canTapSelect)
                      UpdatesRowActions(
                        chapter: chapter,
                        seriesUrl: manga.realUrl,
                        selectedChapters: selectedChapters,
                        selectionAnchor: selectionAnchor,
                        orderedChapters: orderedChapters,
                        refreshSeries: refreshRowActions,
                        hovered: hovered.value,
                      ),
                    DownloadStatusIcon(
                      isDownloaded: (chapter.user.isDownloaded).ifNull(),
                      mangaId: manga.id,
                      chapter: chapter,
                      updateData: updatePair,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TailTile extends HookConsumerWidget {
  const _TailTile({
    required this.chapter,
    required this.updatePair,
    required this.refreshManga,
    required this.refreshRowActions,
    required this.isSelected,
    required this.canTapSelect,
    required this.toggleSelect,
    required this.selectedChapters,
    required this.selectionAnchor,
    required this.orderedChapters,
    required this.desktop,
  });

  final ChapterWithMangaDto chapter;
  final Future<void> Function() updatePair;
  final Future<void> Function() refreshManga;
  final Future<void> Function(Set<int> mangaIds) refreshRowActions;
  final bool isSelected;
  final bool canTapSelect;
  final ValueChanged<ChapterWithMangaDto> toggleSelect;
  final ValueNotifier<Map<int, ChapterDto>> selectedChapters;
  final ValueNotifier<int?> selectionAnchor;
  final List<ChapterDto> orderedChapters;
  final bool desktop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hovered = useState(false);
    final color = (chapter.user.isRead).ifNull()
        ? context.theme.colorScheme.onSurface.withValues(alpha: 0.38)
        : null;
    final manga = chapter.manga;

    // Align with head text: 16px padding + 56px cover + 12px gap.
    const leadingIndent = 68.0;

    void openMenuAt(Offset position) {
      showUpdatesChapterMenu(
        context: context,
        ref: ref,
        position: menuAnchorForPoint(context, position),
        chapter: chapter,
        seriesUrl: manga.realUrl,
        selectedChapters: selectedChapters,
        selectionAnchor: selectionAnchor,
        orderedChapters: orderedChapters,
        refreshSeries: refreshRowActions,
      );
    }

    return Material(
      color: isSelected
          ? desktop
                ? context.theme.colorScheme.primary.withValues(alpha: 0.16)
                : context.theme.colorScheme.secondaryContainer
          : Colors.transparent,
      child: WebRouteLink(
        location: ReaderRoute(
          mangaId: manga.id,
          chapterId: chapter.id,
          showReaderLayoutAnimation: true,
        ).location,
        builder: (context, openInNewTab) => GestureDetector(
          onSecondaryTapDown: desktop
              ? (details) => openMenuAt(details.globalPosition)
              : null,
          child: MouseRegion(
            onEnter: (_) => hovered.value = true,
            onExit: (_) => hovered.value = false,
            child: InkWell(
              onTap: () => WebRouteLink.handleAsyncTap(openInNewTab, () async {
                if (canTapSelect) {
                  toggleSelect(chapter);
                } else {
                  await ReaderRoute(
                    mangaId: manga.id,
                    chapterId: chapter.id,
                    showReaderLayoutAnimation: true,
                  ).push(context);
                  if (!context.mounted) return;
                  await refreshManga();
                }
              }),
              onLongPress: () => toggleSelect(chapter),
              onSecondaryTap: desktop ? null : () => toggleSelect(chapter),
              child: Padding(
                padding: const EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 6,
                  bottom: 6,
                ).onDesktopPageLine(context),
                child: Row(
                  children: [
                    if (desktop && canTapSelect)
                      Checkbox(
                        value: isSelected,
                        visualDensity: VisualDensity.compact,
                        onChanged: (_) => toggleSelect(chapter),
                      ),
                    const SizedBox(width: leadingIndent),
                    if ((chapter.user.isBookmarked).ifNull()) ...[
                      const Icon(FluentIcons.bookmark_24_filled, size: 20),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        chapter.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color:
                              color ??
                              context.theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (desktop && !canTapSelect)
                      UpdatesRowActions(
                        chapter: chapter,
                        seriesUrl: manga.realUrl,
                        selectedChapters: selectedChapters,
                        selectionAnchor: selectionAnchor,
                        orderedChapters: orderedChapters,
                        refreshSeries: refreshRowActions,
                        hovered: hovered.value,
                      ),
                    DownloadStatusIcon(
                      isDownloaded: (chapter.user.isDownloaded).ifNull(),
                      mangaId: manga.id,
                      chapter: chapter,
                      updateData: updatePair,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
