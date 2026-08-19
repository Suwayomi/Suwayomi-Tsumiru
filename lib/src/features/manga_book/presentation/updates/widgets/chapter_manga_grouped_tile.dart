// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../constants/app_sizes.dart';
import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../widgets/server_image.dart';
import '../../../domain/chapter/chapter_model.dart';
import '../../../widgets/download_status_icon.dart';
import '../controller/updates_grouping_controller.dart';

/// A head + N collapsible tail chapters for the same manga on the same day.
///
/// When [tail] is empty this behaves exactly like [ChapterMangaListTile].
class ChapterMangaGroupedTile extends HookConsumerWidget {
  const ChapterMangaGroupedTile({
    super.key,
    required this.head,
    required this.tail,
    required this.updatePairFor,
    required this.refreshManga,
    required this.isSelected,
    required this.canTapSelect,
    required this.toggleSelect,
  });

  final ChapterWithMangaDto head;

  /// Additional chapters for this manga on the same day (already sorted).
  final List<ChapterWithMangaDto> tail;

  /// Returns the no-arg updatePair callback for a given chapter.
  final Future<void> Function() Function(ChapterWithMangaDto) updatePairFor;

  final Future<void> Function() refreshManga;
  final bool isSelected;
  final bool canTapSelect;
  final ValueChanged<ChapterWithMangaDto> toggleSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupingMode = ref.watch(updatesGroupingModeProvider) ??
        UpdatesGroupingMode.disabled;

    // Each group starts expanded or collapsed based on the persisted setting.
    // The user can toggle independently of the global default.
    final isExpanded = useState(groupingMode == UpdatesGroupingMode.expanded);

    final isGroup = tail.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _HeadTile(
          chapter: head,
          isGroup: isGroup,
          tailCount: tail.length,
          isExpanded: isExpanded.value,
          onToggleExpand:
              isGroup ? () => isExpanded.value = !isExpanded.value : null,
          updatePair: updatePairFor(head),
          refreshManga: refreshManga,
          isSelected: isSelected,
          canTapSelect: canTapSelect,
          toggleSelect: toggleSelect,
        ),
        if (isGroup)
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: isExpanded.value
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final chapter in tail)
                        _TailTile(
                          chapter: chapter,
                          updatePair: updatePairFor(chapter),
                          refreshManga: refreshManga,
                          isSelected: isSelected,
                          canTapSelect: canTapSelect,
                          toggleSelect: toggleSelect,
                        ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Head tile — the representative chapter, with an optional expand toggle
// ---------------------------------------------------------------------------

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
    final color = (chapter.isRead).ifNull() ? Colors.grey : null;
    final manga = chapter.manga;

    return Material(
      color: isSelected
          ? (context.isDarkMode ? Colors.grey.shade700 : Colors.grey.shade300)
          : Colors.transparent,
      child: InkWell(
        onTap: () async {
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
        },
        onLongPress: () => toggleSelect(chapter),
        onSecondaryTap: () => toggleSelect(chapter),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              if (manga.thumbnailUrl != null)
                ClipRRect(
                  borderRadius: KBorderRadius.r8.radius,
                  child: InkWell(
                    onTap: () async {
                      if (canTapSelect) {
                        toggleSelect(chapter);
                        return;
                      }
                      await MangaRoute(mangaId: manga.id).push(context);
                      if (!context.mounted) return;
                      await refreshManga();
                    },
                    child: ServerImage(
                      imageUrl: manga.thumbnailUrl ?? "",
                      size: const Size(56, 80),
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
                        if ((chapter.isBookmarked).ifNull()) ...[
                          const Icon(Icons.bookmark_rounded, size: 20),
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
                            color ?? context.theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (isGroup)
                      GestureDetector(
                        onTap: onToggleExpand,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                context.l10n.updatesGroupingShowMore(tailCount),
                                style: context.textTheme.labelSmall?.copyWith(
                                  color: context.theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 2),
                              Icon(
                                isExpanded
                                    ? Icons.expand_less_rounded
                                    : Icons.expand_more_rounded,
                                size: 14,
                                color: context.theme.colorScheme.primary,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              DownloadStatusIcon(
                isDownloaded: (chapter.isDownloaded).ifNull(),
                mangaId: manga.id,
                chapter: chapter,
                updateData: updatePair,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tail tile — a lightweight row without the cover image
// ---------------------------------------------------------------------------

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
    final color = (chapter.isRead).ifNull() ? Colors.grey : null;
    final manga = chapter.manga;

    // Indented to align with the text column of the head tile.
    // 16 (h-pad) + 56 (cover) + 12 (gap) = 84
    const leadingIndent = 84.0;

    return Material(
      color: isSelected
          ? (context.isDarkMode ? Colors.grey.shade700 : Colors.grey.shade300)
          : Colors.transparent,
      child: InkWell(
        onTap: () async {
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
        },
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
              if ((chapter.isBookmarked).ifNull()) ...[
                const Icon(Icons.bookmark_rounded, size: 16),
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
                isDownloaded: (chapter.isDownloaded).ifNull(),
                mangaId: manga.id,
                chapter: chapter,
                updateData: updatePair,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
