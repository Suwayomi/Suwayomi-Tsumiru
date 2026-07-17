// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/theme/brand.dart';
import '../../../domain/chapter/chapter_model.dart';
import '../../../domain/manga/manga_model.dart';

/// Compact chapter-number tile for the grid view of the chapter list.
/// Same tap/long-press/right-click semantics as [ChapterListTile].
class ChapterGridTile extends StatelessWidget {
  const ChapterGridTile({
    super.key,
    required this.manga,
    required this.chapter,
    required this.toggleSelect,
    this.canTapSelect = false,
    this.isSelected = false,
  });
  final MangaDto manga;
  final ChapterDto chapter;
  final ValueChanged<ChapterDto> toggleSelect;
  final bool canTapSelect;
  final bool isSelected;

  /// "1145" for whole numbers, "10.5" for decimals; falls back to the source
  /// order for chapters without a parsed number.
  static String label(ChapterDto chapter) {
    final number = chapter.chapterNumber;
    if (number < 0) return '#${chapter.sourceOrder}';
    return number == number.roundToDouble()
        ? number.toInt().toString()
        : number.toString();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.theme.colorScheme;
    final isRead = chapter.isRead.ifNull();
    final inProgress = !isRead &&
        chapter.lastPageRead.getValueOnNullOrNegative() != 0;

    final Color background;
    final Color textColor;
    Border? border;
    if (isSelected) {
      background = cs.primary.withValues(alpha: 0.22);
      textColor = cs.onSurface;
      border = Border.all(color: cs.primary);
    } else if (isRead) {
      // Read chapters recede: flat, dim.
      background = cs.onSurface.withValues(alpha: 0.02);
      textColor = cs.outline;
      border = Border.all(color: cs.outlineVariant);
    } else {
      background = cs.surfaceContainer;
      textColor = cs.onSurface;
      border = Border.all(color: cs.outlineVariant);
    }

    Widget tile = Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: inProgress && !isSelected ? null : border,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label(chapter),
                style: TextStyle(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: isRead ? FontWeight.w500 : FontWeight.w600,
                ),
              ),
            ),
          ),
          if (chapter.isBookmarked.ifNull())
            Positioned(
              top: -1,
              right: 5,
              child: Icon(
                Icons.bookmark_rounded,
                size: 13,
                color: isRead ? cs.outline : cs.primary,
              ),
            ),
          if (inProgress)
            Positioned(
              bottom: 3,
              child: Text(
                context.l10n.page(
                  chapter.lastPageRead.getValueOnNullOrNegative() + 1,
                ),
                style: TextStyle(
                  color: cs.secondary,
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else if (chapter.isDownloaded.ifNull())
            Positioned(
              bottom: 5,
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: brandGradient(cs),
                ),
              ),
            ),
        ],
      ),
    );

    if (inProgress && !isSelected) {
      // "Continue here" — gradient ring + soft glow around the tile.
      tile = Container(
        decoration: BoxDecoration(
          gradient: brandGradient(cs),
          borderRadius: BorderRadius.circular(13.5),
          boxShadow: [
            BoxShadow(
              color: cs.primary.withValues(alpha: 0.3),
              blurRadius: 10,
              spreadRadius: -2,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(1.5),
        child: tile,
      );
    }

    return GestureDetector(
      key: Key("manga-${manga.id}-chapter-${chapter.id}"),
      onSecondaryTap: () => toggleSelect(chapter),
      child: Tooltip(
        message: chapter.name,
        waitDuration: const Duration(milliseconds: 500),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: canTapSelect
              ? () => toggleSelect(chapter)
              : () => ReaderRoute(
                    mangaId: manga.id,
                    chapterId: chapter.id,
                    showReaderLayoutAnimation: true,
                  ).push(context),
          onLongPress: () => toggleSelect(chapter),
          child: tile,
        ),
      ),
    );
  }
}
