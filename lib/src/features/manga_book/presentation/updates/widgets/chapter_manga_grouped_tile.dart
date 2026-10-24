// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../constants/app_sizes.dart';
import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/motion/reduce_motion.dart';
import '../../../../../widgets/hover_tap_target.dart';
import '../../../../../widgets/server_image.dart';
import '../../../../../widgets/web_route_link.dart';
import '../../../domain/chapter/chapter_model.dart';
import '../../../widgets/download_status_icon.dart';
import '../controller/updates_grouping_controller.dart';

/// An empty [tail] behaves like ChapterMangaListTile.
class ChapterMangaGroupedTile extends HookConsumerWidget {
  const ChapterMangaGroupedTile({
    super.key,
    required this.head,
    required this.tail,
    required this.updatePairFor,
    required this.refreshManga,
    required this.isSelectedFor,
    required this.canTapSelect,
    required this.toggleSelect,
  });

  final ChapterWithMangaDto head;

  /// Additional chapters for this manga on the same day (already sorted).
  final List<ChapterWithMangaDto> tail;

  final Future<void> Function() Function(ChapterWithMangaDto) updatePairFor;

  final Future<void> Function() refreshManga;

  /// Selection is per chapter: head and tail rows can be selected independently.
  final bool Function(ChapterWithMangaDto) isSelectedFor;
  final bool canTapSelect;
  final ValueChanged<ChapterWithMangaDto> toggleSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupingMode =
        ref.watch(updatesGroupingModeProvider) ?? UpdatesGroupingMode.disabled;

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
                  isSelected: isSelectedFor(chapter),
                  canTapSelect: canTapSelect,
                  toggleSelect: toggleSelect,
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
          isSelected: isSelectedFor(head),
          canTapSelect: canTapSelect,
          toggleSelect: toggleSelect,
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


class _HeadTile extends StatelessWidget {
  const _HeadTile({
    required this.chapter,
    required this.isGroup,
    required this.tailCount,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.updatePair,
    required this.refreshManga,
    required this.isSelected,
    required this.canTapSelect,
    required this.toggleSelect,
  });

  final ChapterWithMangaDto chapter;
  final bool isGroup;
  final int tailCount;
  final bool isExpanded;
  final VoidCallback? onToggleExpand;
  final Future<void> Function() updatePair;
  final Future<void> Function() refreshManga;
  final bool isSelected;
  final bool canTapSelect;
  final ValueChanged<ChapterWithMangaDto> toggleSelect;

  @override
  Widget build(BuildContext context) {
    final color = (chapter.user.isRead).ifNull()
        ? context.theme.colorScheme.onSurface.withValues(alpha: 0.38)
        : null;
    final manga = chapter.manga;

    return Material(
      color: isSelected
          ? context.theme.colorScheme.secondaryContainer
          : Colors.transparent,
      child: WebRouteLink(
        location: ReaderRoute(
          mangaId: manga.id,
          chapterId: chapter.id,
          showReaderLayoutAnimation: true,
        ).location,
        builder: (context, openInNewTab) => InkWell(
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
          onSecondaryTap: () => toggleSelect(chapter),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                if (manga.thumbnailUrl != null)
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
                            await MangaRoute(mangaId: manga.id).push(context);
                            if (!context.mounted) return;
                            await refreshManga();
                          },
                        ),
                        child: ServerImage(
                          imageUrl: manga.thumbnailUrl ?? "",
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
                            const Icon(FluentIcons.bookmark_24_filled, size: 20),
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
                                          color:
                                              context.theme.colorScheme.primary,
                                          decoration: hovered
                                              ? TextDecoration.underline
                                              : TextDecoration.none,
                                        ),
                                  ),
                                  const SizedBox(width: 2),
                                  Icon(
                                    isExpanded
                                        ? FluentIcons.chevron_up_24_regular
                                        : FluentIcons.chevron_down_24_regular,
                                    size: 14,
                                    color: context.theme.colorScheme.primary,
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
    );
  }
}


class _TailTile extends StatelessWidget {
  const _TailTile({
    required this.chapter,
    required this.updatePair,
    required this.refreshManga,
    required this.isSelected,
    required this.canTapSelect,
    required this.toggleSelect,
  });

  final ChapterWithMangaDto chapter;
  final Future<void> Function() updatePair;
  final Future<void> Function() refreshManga;
  final bool isSelected;
  final bool canTapSelect;
  final ValueChanged<ChapterWithMangaDto> toggleSelect;

  @override
  Widget build(BuildContext context) {
    final color = (chapter.user.isRead).ifNull()
        ? context.theme.colorScheme.onSurface.withValues(alpha: 0.38)
        : null;
    final manga = chapter.manga;

    // Align with head text: 16px padding + 56px cover + 12px gap.
    const leadingIndent = 84.0;

    return Material(
      color: isSelected
          ? context.theme.colorScheme.secondaryContainer
          : Colors.transparent,
      child: WebRouteLink(
        location: ReaderRoute(
          mangaId: manga.id,
          chapterId: chapter.id,
          showReaderLayoutAnimation: true,
        ).location,
        builder: (context, openInNewTab) => InkWell(
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
          onSecondaryTap: () => toggleSelect(chapter),
          child: Padding(
            padding: const EdgeInsets.only(
              left: leadingIndent,
              right: 16,
              top: 6,
              bottom: 6,
            ),
            child: Row(
              children: [
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
                          color ?? context.theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
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
    );
  }
}
