// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:math' as math;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../widgets/hover_tap_target.dart';
import '../../../../../widgets/manga_cover/grid/manga_cover_grid_tile.dart';
import '../../../domain/chapter/chapter_model.dart';
import '../../../domain/manga/manga_model.dart';
import '../../../domain/updates/updates_grouping.dart';
import '../../manga_details/widgets/chapter_context_menu.dart';
import 'updates_row_actions.dart';

class UpdatesGridCard extends HookConsumerWidget {
  const UpdatesGridCard({
    super.key,
    required this.group,
    required this.refreshManga,
    required this.refreshRowActions,
    required this.isSelectedFor,
    required this.canTapSelect,
    required this.toggleSelect,
    required this.selectedChapters,
    required this.selectionAnchor,
    required this.orderedChapters,
  });

  final UpdatesGroupedEntry group;
  final Future<void> Function() refreshManga;
  final Future<void> Function(Set<int> mangaIds) refreshRowActions;
  final bool Function(ChapterWithMangaDto) isSelectedFor;
  final bool canTapSelect;
  final ValueChanged<ChapterWithMangaDto> toggleSelect;
  final ValueNotifier<Map<int, ChapterDto>> selectedChapters;
  final ValueNotifier<int?> selectionAnchor;
  final List<ChapterDto> orderedChapters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final desktop = context.usesDesktopShell;
    final hovered = useState(false);
    final head = group.head;
    final tail = group.tail;
    final manga = head.manga;
    final chapters = [head, ...tail]
      ..sort((a, b) {
        final fetched = (int.tryParse(b.fetchedAt) ?? 0).compareTo(
          int.tryParse(a.fetchedAt) ?? 0,
        );
        if (fetched != 0) return fetched;
        return b.sourceOrder.compareTo(a.sourceOrder);
      });
    final unread = [
      for (final c in chapters)
        if (!(c.user.isRead).ifNull()) c,
    ].length;

    void openMenuAt(Offset position) {
      showUpdatesChapterMenu(
        context: context,
        ref: ref,
        position: menuAnchorForPoint(context, position),
        chapter: head,
        seriesUrl: manga.realUrl,
        selectedChapters: selectedChapters,
        selectionAnchor: selectionAnchor,
        orderedChapters: orderedChapters,
        refreshSeries: refreshRowActions,
      );
    }

    Future<void> openChapter(ChapterWithMangaDto chapter) async {
      await ReaderRoute(
        mangaId: manga.id,
        chapterId: chapter.id,
        showReaderLayoutAnimation: true,
      ).push(context);
      if (!context.mounted) return;
      await refreshManga();
    }

    return GestureDetector(
      onSecondaryTapDown: desktop
          ? (details) => openMenuAt(details.globalPosition)
          : null,
      child: MouseRegion(
        onEnter: (_) => hovered.value = true,
        onExit: (_) => hovered.value = false,
        child: Stack(
          children: [
            MangaCoverGridTile(
              coverUrlOverride: manga.displayCoverUrl,
              coverVersionOverride: manga.coverVersion,
              fallbackImageUrlOverride: manga.thumbnailUrl,
              fallbackCoverVersionOverride: manga.thumbnailUrlLastFetched,
              titleOverride: manga.title,
              badgeCountOverride: unread > 0 ? unread : null,
              subtitle: head.name,
              subtitleSuffix: tail.isNotEmpty
                  ? Builder(
                      builder: (anchorContext) => HoverTapTarget(
                        builder: (suffixContext, suffixHovered) =>
                            GestureDetector(
                              onTap: () => showGroupChapters(
                                anchorContext: anchorContext,
                                readerContext: context,
                                seriesTitle: manga.title,
                                chapters: chapters,
                                openChapter: openChapter,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    ' · ',
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.5,
                                      color: suffixContext
                                          .theme
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                  Text(
                                    '+${tail.length}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.5,
                                      color: suffixContext
                                          .theme
                                          .colorScheme
                                          .primary,
                                      decoration: suffixHovered
                                          ? TextDecoration.underline
                                          : TextDecoration.none,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                      ),
                    )
                  : null,
              dimmed: unread == 0,
              selected: isSelectedFor(head),
              showCountBadges: true,
              showDarkOverlay: false,
              titleBelow: true,
              linkLocation: ReaderRoute(
                mangaId: manga.id,
                chapterId: head.id,
                showReaderLayoutAnimation: true,
              ).location,
              onPressed: () {
                if (canTapSelect) {
                  toggleSelect(head);
                } else {
                  unawaited(openChapter(head));
                }
              },
              onLongPress: () => toggleSelect(head),
            ),
            if (desktop && hovered.value && !canTapSelect)
              Positioned(
                top: 4,
                right: 4,
                child: Builder(
                  builder: (buttonContext) => DecoratedBox(
                    decoration: BoxDecoration(
                      color: buttonContext.theme.colorScheme.surfaceContainer,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      tooltip: buttonContext.l10n.more,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(
                        FluentIcons.more_vertical_24_regular,
                        size: 20,
                      ),
                      onPressed: () {
                        final box =
                            buttonContext.findRenderObject() as RenderBox?;
                        if (box == null) return;
                        showUpdatesChapterMenu(
                          context: context,
                          ref: ref,
                          position: menuAnchorForRect(
                            context,
                            box.localToGlobal(Offset.zero) & box.size,
                          ),
                          chapter: head,
                          seriesUrl: manga.realUrl,
                          selectedChapters: selectedChapters,
                          selectionAnchor: selectionAnchor,
                          orderedChapters: orderedChapters,
                          refreshSeries: refreshRowActions,
                        );
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> showGroupChapters({
  required BuildContext anchorContext,
  required BuildContext readerContext,
  required String seriesTitle,
  required List<ChapterWithMangaDto> chapters,
  required Future<void> Function(ChapterWithMangaDto) openChapter,
}) {
  final box = anchorContext.findRenderObject()! as RenderBox;
  final overlay =
      Navigator.of(anchorContext).overlay!.context.findRenderObject()!
          as RenderBox;
  final rect = Rect.fromPoints(
    box.localToGlobal(Offset.zero, ancestor: overlay),
    box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
  );
  return showMenu<void>(
    context: anchorContext,
    position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
    constraints: const BoxConstraints.tightFor(width: 320),
    color: anchorContext.colorScheme.surfaceContainer,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: anchorContext.colorScheme.outlineVariant),
    ),
    items: [
      PopupMenuItem<void>(
        enabled: false,
        padding: EdgeInsets.zero,
        child: Builder(
          builder: (popupContext) => SizedBox(
            height: math.min(460, 48 + chapters.length * 52).toDouble(),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 16, right: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          seriesTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: popupContext.textTheme.titleSmall,
                        ),
                      ),
                      IconButton(
                        tooltip: popupContext.l10n.close,
                        icon: const Icon(FluentIcons.dismiss_24_regular),
                        onPressed: () => Navigator.of(popupContext).pop(),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: chapters.length,
                    itemBuilder: (context, index) {
                      final chapter = chapters[index];
                      final read = (chapter.user.isRead).ifNull();
                      return InkWell(
                        onTap: () {
                          Navigator.of(popupContext).pop();
                          openChapter(chapter);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Text(
                            chapter.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: read
                                  ? context.theme.colorScheme.onSurface
                                        .withValues(alpha: 0.38)
                                  : context.theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}
