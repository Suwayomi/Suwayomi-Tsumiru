// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../../../constants/app_sizes.dart';
import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../widgets/server_image.dart';
import '../../../domain/chapter/chapter_model.dart';
import '../../../widgets/download_status_icon.dart';

class ChapterMangaListTile extends StatelessWidget {
  const ChapterMangaListTile({
    super.key,
    required this.chapterWithMangaDto,
    required this.updatePair,
    required this.toggleSelect,
    this.canTapSelect = false,
    this.isSelected = false,
  });
  final ChapterWithMangaDto chapterWithMangaDto;
  final AsyncCallback updatePair;
  final ValueChanged<ChapterWithMangaDto> toggleSelect;
  final bool canTapSelect;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final color = (chapterWithMangaDto.isRead).ifNull() ? Colors.grey : null;
    final manga = chapterWithMangaDto.manga;
    // Custom Row (rather than ListTile's height-constrained `leading`) so the
    // cover renders at the standard portrait size used on the History list.
    return Material(
      color: isSelected
          ? (context.isDarkMode ? Colors.grey.shade700 : Colors.grey.shade300)
          : Colors.transparent,
      child: InkWell(
        onTap: () {
          if (canTapSelect) {
            toggleSelect(chapterWithMangaDto);
          } else {
            ReaderRoute(
              mangaId: manga.id,
              chapterId: chapterWithMangaDto.id,
              showReaderLayoutAnimation: true,
            ).push(context);
          }
        },
        onLongPress: () => toggleSelect(chapterWithMangaDto),
        onSecondaryTap: () => toggleSelect(chapterWithMangaDto),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              if (manga.thumbnailUrl != null)
                ClipRRect(
                  borderRadius: KBorderRadius.r8.radius,
                  child: InkWell(
                    onTap: () => MangaRoute(mangaId: manga.id).push(context),
                    child: ServerImage(
                      imageUrl: manga.thumbnailUrl ?? "",
                      size: const Size(56, 80),
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
                        if ((chapterWithMangaDto.isBookmarked).ifNull()) ...[
                          const Icon(Icons.bookmark_rounded, size: 20),
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
                        color: color ?? context.theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Gap(8),
              DownloadStatusIcon(
                isDownloaded: (chapterWithMangaDto.isDownloaded).ifNull(),
                mangaId: manga.id,
                chapter: chapterWithMangaDto,
                updateData: updatePair,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
