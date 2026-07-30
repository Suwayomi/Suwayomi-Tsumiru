// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../../constants/app_sizes.dart';
import '../../../features/manga_book/domain/manga/manga_model.dart';
import '../../server_image.dart';
import '../widgets/continue_reading_button.dart';
import '../widgets/manga_badges.dart';

class MangaCoverListTile extends StatelessWidget {
  const MangaCoverListTile({
    super.key,
    required this.manga,
    this.onPressed,
    this.onLongPress,
    this.onContinueReading,
    this.trailing,
    this.showBadges = true,
    this.showCountBadges = false,
    this.selected = false,
    this.scale = 1.0,
    this.limitTitleLines = true,
  });

  final MangaDto manga;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;

  /// When non-null, a play button at the row end opens the next unread chapter.
  final VoidCallback? onContinueReading;

  /// An optional action widget pinned to the row end (e.g. a Migrate button).
  final Widget? trailing;
  final bool showCountBadges;
  final bool showBadges;
  final bool selected;

  /// Library list-size multiplier. Scales the cover box; the caller scales the
  /// text through a [MediaQuery] textScaler so the row grows as one unit.
  final double scale;

  /// Cap the title at three ellipsized lines. Off lets it wrap in full, which
  /// only shows if the caller also lets the row grow.
  final bool limitTitleLines;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: selected
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.24)
          : Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        onLongPress: onLongPress,
        child: Row(
          children: [
          Padding(
            padding: KEdgeInsets.a8.size,
            child: ClipRRect(
              borderRadius: KBorderRadius.r8.radius,
              child: ServerImage(
                imageUrl: manga.thumbnailUrl ?? "",
                // Decode at display size — see the grid tile.
                memCacheWidth: (kCompactCoverWidth *
                        scale *
                        MediaQuery.devicePixelRatioOf(context))
                    .round()
                    .clamp(1, 1 << 16),
                size: Size(
                  kCompactCoverWidth * scale,
                  mangaCoverBoxHeight(kCompactCoverWidth * scale,
                      coverInset: 0),
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: KEdgeInsets.h8.size,
              // Skia collapses an uncapped ellipsis to one line, so uncapped
              // text has to clip instead.
              child: Text(
                manga.title,
                softWrap: true,
                overflow: limitTitleLines
                    ? TextOverflow.ellipsis
                    : TextOverflow.clip,
                maxLines: limitTitleLines ? 3 : null,
              ),
            ),
          ),
            if (showBadges)
              MangaBadgesRow(manga: manga, showCountBadges: showCountBadges),
            if (onContinueReading != null)
              Padding(
                padding: KEdgeInsets.h8.size,
                child: ContinueReadingButton(
                  onPressed: onContinueReading!,
                  size: 28,
                ),
              ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
