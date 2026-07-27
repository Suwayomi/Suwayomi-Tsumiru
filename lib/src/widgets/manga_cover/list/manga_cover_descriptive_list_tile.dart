// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../constants/app_sizes.dart';
import '../../../constants/enum.dart';
import '../../../features/browse_center/domain/source/source_model.dart';
import '../../../features/manga_book/domain/manga/manga_model.dart';
import '../../../routes/router_config.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../grid/manga_cover_grid_tile.dart';
import '../widgets/manga_badges.dart';
import '../widgets/manga_chips.dart';

class MangaCoverDescriptiveListTile extends StatelessWidget {
  const MangaCoverDescriptiveListTile({
    super.key,
    required this.manga,
    this.onPressed,
    this.onLongPress,
    this.onContinueReading,
    this.onTitleClicked,
    this.showBadges = true,
    this.showCountBadges = true,
    this.selected = false,
    this.belowStatus,
    this.titleMaxLines = 2,
  });
  final MangaDto manga;
  final bool showBadges;
  final bool showCountBadges;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;

  /// When non-null, a play button is overlaid on the cover that opens the next
  /// unread chapter.
  final VoidCallback? onContinueReading;
  final ValueChanged<String?>? onTitleClicked;
  final bool selected;
  /// Optional widget rendered below the status/source line (details screen only).
  /// When null — the default for library/browse callers — nothing is rendered.
  final Widget? belowStatus;

  /// Null lets the title wrap to its full length, which is what the details
  /// screen wants (Mihon caps it nowhere). List rows keep 2 so they stay even.
  final int? titleMaxLines;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: selected
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.24)
          : Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        onLongPress: onLongPress,
        child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: kDescriptiveCoverWidth,
              height: mangaCoverBoxHeight(kDescriptiveCoverWidth),
              child: MangaCoverGridTile(
                manga: manga,
                showBadges: false,
                showTitle: false,
                showDarkOverlay: false,
                onContinueReading: onContinueReading,
              ),
            ),
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: onTitleClicked != null
                          ? () => onTitleClicked!(manga.title)
                          : null,
                      child: Text(
                        manga.title,
                        style: context.textTheme.titleLarge,
                        overflow: titleMaxLines == null
                            ? TextOverflow.clip
                            : TextOverflow.ellipsis,
                        maxLines: titleMaxLines,
                        semanticsLabel: manga.title,
                      ),
                    ),
                    Gap(8),
                    InkWell(
                      onTap: onTitleClicked != null && manga.author.isNotBlank
                          ? () => onTitleClicked!(manga.author)
                          : null,
                      child: Text(
                        manga.author ?? context.l10n.unknownAuthor,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.bodyMedium,
                      ),
                    ),
                    Gap(8),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ...[
                          Icon(
                            MangaStatus.fromJson(manga.status.name).icon,
                            size: 16,
                            color: context.textTheme.bodySmall?.color,
                          ),
                          Text(
                            " ${MangaStatus.fromJson(manga.status.name).toLocale(context)}",
                            style: context.textTheme.bodySmall,
                          ),
                        ],
                        if (manga.source?.displayName != null) ...[
                          Text(" • "),
                          InkWell(
                            onTap: (manga.source?.id).isNotBlank
                                ? () => SourceTypeRoute(
                                        sourceId: manga.source!.id,
                                        sourceType: SourceType.POPULAR)
                                    .go(context)
                                : null,
                            child: Text(
                              manga.source?.displayName ??
                                  context.l10n.unknownSource,
                              style: context.textTheme.bodySmall,
                            ),
                          ),
                        ]
                      ],
                    ),
                    if (belowStatus != null) ...[
                      Gap(4),
                      belowStatus!,
                    ],
                    // if (showLastReadChapter) ...[
                    //   Padding(
                    //     padding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
                    //     child: Text(
                    //       manga.lastChapterRead?.name ?? "",
                    //       overflow: TextOverflow.ellipsis,
                    //       style: context.textTheme.bodySmall,
                    //     ),
                    //   ),
                    //   Padding(
                    //     padding: const EdgeInsets.symmetric(vertical: 2.0),
                    //     child: Text(
                    //       manga.lastReadAt.toDaysAgoFromSeconds ?? "",
                    //       overflow: TextOverflow.ellipsis,
                    //       style: context.textTheme.bodySmall,
                    //     ),
                    //   ),
                    // ],
                    if (showBadges)
                      context.isTablet
                          ? MangaChipsRow(
                              manga: manga,
                              showCountBadges: showCountBadges,
                            )
                          : MangaBadgesRow(
                              padding: KEdgeInsets.v8.size,
                              manga: manga,
                              showCountBadges: showCountBadges,
                            ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
