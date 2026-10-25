// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../../../constants/app_sizes.dart';
import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../widgets/server_image.dart';
import '../../../../../widgets/web_route_link.dart';
import '../../../domain/chapter/chapter_model.dart';
import '../../../domain/manga/manga_model.dart';
import '../../../widgets/download_status_icon.dart';

class ChapterMangaListTile extends StatelessWidget {
  const ChapterMangaListTile({
    super.key,
    required this.chapterWithMangaDto,
    required this.updatePair,
    required this.refreshManga,
    required this.toggleSelect,
    this.canTapSelect = false,
    this.isSelected = false,
  });
  final ChapterWithMangaDto chapterWithMangaDto;
  final AsyncCallback updatePair;
  final AsyncCallback refreshManga;
  final ValueChanged<ChapterWithMangaDto> toggleSelect;
  final bool canTapSelect;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final color = (chapterWithMangaDto.user.isRead).ifNull()
        ? context.theme.colorScheme.onSurface.withValues(alpha: 0.38)
        : null;
    final manga = chapterWithMangaDto.manga;
    final readerLocation = ReaderRoute(
      mangaId: manga.id,
      chapterId: chapterWithMangaDto.id,
      showReaderLayoutAnimation: true,
    ).location;
    return Material(
      color: isSelected
          ? context.theme.colorScheme.secondaryContainer
          : Colors.transparent,
      child: WebRouteLink(
        location: readerLocation,
        builder: (context, openInNewTab) => InkWell(
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
          onSecondaryTap: () => toggleSelect(chapterWithMangaDto),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
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
                            // Cover taps must honour multi-selection instead of navigating away.
                            if (canTapSelect) {
                              toggleSelect(chapterWithMangaDto);
                              return;
                            }
                            await MangaRoute(mangaId: manga.id).push(context);
                            if (!context.mounted) return;
                            await refreshManga();
                          },
                        ),
                        child: ServerImage(
                          imageUrl: manga.displayCoverUrl,
                          fallbackImageUrl: manga.thumbnailUrl,
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
                            const Icon(FluentIcons.bookmark_24_filled, size: 20),
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
    );
  }
}
