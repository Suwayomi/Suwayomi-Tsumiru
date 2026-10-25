// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../constants/app_sizes.dart';
import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../widgets/server_image.dart';
import '../../../../../widgets/web_route_link.dart';
import '../../../domain/chapter/chapter_model.dart';
import '../../../widgets/download_status_icon.dart';
import '../../manga_details/widgets/chapter_context_menu.dart';
import 'updates_row_actions.dart';

class ChapterMangaListTile extends HookConsumerWidget {
  const ChapterMangaListTile({
    super.key,
    required this.chapterWithMangaDto,
    required this.updatePair,
    required this.refreshManga,
    required this.refreshRowActions,
    required this.toggleSelect,
    required this.selectedChapters,
    required this.selectionAnchor,
    required this.orderedChapters,
    this.canTapSelect = false,
    this.isSelected = false,
    this.desktop = false,
  });
  final ChapterWithMangaDto chapterWithMangaDto;
  final AsyncCallback updatePair;
  final AsyncCallback refreshManga;
  final Future<void> Function(Set<int> mangaIds) refreshRowActions;
  final ValueChanged<ChapterWithMangaDto> toggleSelect;
  final ValueNotifier<Map<int, ChapterDto>> selectedChapters;
  final ValueNotifier<int?> selectionAnchor;
  final List<ChapterDto> orderedChapters;
  final bool canTapSelect;
  final bool isSelected;
  final bool desktop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hovered = useState(false);
    final color = (chapterWithMangaDto.user.isRead).ifNull()
        ? context.theme.colorScheme.onSurface.withValues(alpha: 0.38)
        : null;
    final manga = chapterWithMangaDto.manga;
    final readerLocation = ReaderRoute(
      mangaId: manga.id,
      chapterId: chapterWithMangaDto.id,
      showReaderLayoutAnimation: true,
    ).location;

    void openMenuAt(Offset position) {
      showUpdatesChapterMenu(
        context: context,
        ref: ref,
        position: menuAnchorForPoint(context, position),
        chapter: chapterWithMangaDto,
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
        location: readerLocation,
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
                  toggleSelect(chapterWithMangaDto);
                } else {
                  await ReaderRoute(
                    mangaId: manga.id,
                    chapterId: chapterWithMangaDto.id,
                    showReaderLayoutAnimation: true,
                  ).push(context);
                  // Refresh the whole series after reading because navigation may change other chapter rows too.
                  if (!context.mounted) return;
                  await refreshManga();
                }
              }),
              onLongPress: () => toggleSelect(chapterWithMangaDto),
              onSecondaryTap: desktop
                  ? null
                  : () => toggleSelect(chapterWithMangaDto),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    if (desktop && canTapSelect)
                      Checkbox(
                        value: isSelected,
                        visualDensity: VisualDensity.compact,
                        onChanged: (_) => toggleSelect(chapterWithMangaDto),
                      ),
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
                                // Cover taps must honour multi-selection instead of navigating away.
                                if (canTapSelect) {
                                  toggleSelect(chapterWithMangaDto);
                                  return;
                                }
                                await MangaRoute(mangaId: manga.id)
                                    .push(context);
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
                    const Gap(12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              if ((chapterWithMangaDto.user.isBookmarked)
                                  .ifNull()) ...[
                                const Icon(
                                  FluentIcons.bookmark_24_filled,
                                  size: 20,
                                ),
                                const Gap(4),
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
                          const Gap(4),
                          Text(
                            chapterWithMangaDto.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color:
                                  color ??
                                  context.theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Gap(8),
                    if (desktop)
                      SizedBox(
                        width: 84,
                        child: Text(
                          int.tryParse(chapterWithMangaDto.fetchedAt)
                              .toShortTimeFromSeconds(context),
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
                        chapter: chapterWithMangaDto,
                        seriesUrl: manga.realUrl,
                        selectedChapters: selectedChapters,
                        selectionAnchor: selectionAnchor,
                        orderedChapters: orderedChapters,
                        refreshSeries: refreshRowActions,
                        hovered: hovered.value,
                      ),
                    DownloadStatusIcon(
                      isDownloaded: (chapterWithMangaDto.user.isDownloaded)
                          .ifNull(),
                      mangaId: manga.id,
                      chapter: chapterWithMangaDto,
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
