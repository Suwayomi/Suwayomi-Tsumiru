// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../../constants/app_sizes.dart';
import '../../../constants/gen/assets.gen.dart';
import '../../../features/manga_book/domain/manga/manga_model.dart';
import '../../../features/manga_book/presentation/manga_thumbnail_viewer/manga_thumbnail_viewer.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../server_image.dart';
import '../widgets/continue_reading_button.dart';
import '../widgets/manga_badges.dart';

class MangaCoverGridTile extends StatelessWidget {
  const MangaCoverGridTile({
    super.key,
    required this.manga,
    this.onPressed,
    this.onLongPress,
    this.onContinueReading,
    this.showTitle = true,
    this.showBadges = true,
    this.showCountBadges = false,
    this.showDarkOverlay = true,
    this.selected = false,
  });
  final MangaDto manga;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;

  /// When non-null, a play button is overlaid on the cover that opens the next
  /// unread chapter. The library list supplies this only when the toggle is on
  /// and a target chapter exists.
  final VoidCallback? onContinueReading;
  final bool showCountBadges;
  final bool showTitle;
  final bool showBadges;
  final bool showDarkOverlay;

  /// Multi-select highlight: a primary-tinted border + check on the
  /// library selection.
  final bool selected;
  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onPressed ??
          () => Navigator.push(
                context,
                PageRouteBuilder(
                  fullscreenDialog: true,
                  opaque: false,
                  pageBuilder: (context, _, __) => MangaThumbnailViewer(
                    imageUrl: manga.thumbnailUrl ?? "",
                  ),
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) {
                    const begin = Offset(-1.0, 0.0);
                    const end = Offset.zero;
                    const curve = Curves.ease;

                    final tween = Tween(begin: begin, end: end);
                    final curvedAnimation = CurvedAnimation(
                      parent: animation,
                      curve: curve,
                    );

                    return SlideTransition(
                      position: tween.animate(curvedAnimation),
                      child: child,
                    );
                  },
                ),
              ),
      onLongPress: onLongPress,
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: KBorderRadius.r12.radius,
          side: selected
              ? BorderSide(color: context.theme.colorScheme.primary, width: 3)
              : BorderSide.none,
        ),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            _selectableChild(context),
            if (selected)
              Positioned(
                top: 4,
                right: 4,
                child: Icon(
                  Icons.check_circle_rounded,
                  color: context.theme.colorScheme.primary,
                  shadows: const [Shadow(blurRadius: 4)],
                ),
              ),
            // No title to flow beside (cover-only / descriptive-list cover):
            // overlay the button on the cover corner. With a title, the button
            // lives in the footer row instead so it can't cover the text.
            if (onContinueReading != null && !selected && !showTitle)
              Positioned(
                right: 6,
                bottom: 6,
                child: ContinueReadingButton(onPressed: onContinueReading!),
              ),
          ],
        ),
      ),
    );
  }

  Widget _selectableChild(BuildContext context) {
    return GridTile(
          header: showBadges
              ? MangaBadgesRow(manga: manga, showCountBadges: showCountBadges)
              : null,
          footer: showTitle
              ? ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  dense: true,
                  title: Text(
                    manga.title,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                  // The button shares the footer row: the title takes the
                  // remaining width, so it can never sit under the button.
                  trailing: onContinueReading != null
                      ? ContinueReadingButton(
                          onPressed: onContinueReading!,
                          size: 28,
                          iconSize: 16,
                        )
                      : null,
                )
              : null,
          child: manga.thumbnailUrl.isNotBlank
              ? Container(
                  foregroundDecoration: BoxDecoration(
                    border: Border.all(
                      width: 0,
                      color: context.theme.canvasColor,
                    ),
                    boxShadow: showDarkOverlay
                        ? [
                            BoxShadow(
                              color: context.theme.canvasColor
                                  .withValues(alpha: .5),
                            )
                          ]
                        : null,
                    gradient: showTitle
                        ? LinearGradient(
                            begin: Alignment.center,
                            end: Alignment.bottomCenter,
                            colors: [
                              context.theme.canvasColor.withValues(alpha: 0),
                              context.theme.canvasColor.withValues(alpha: 0.4),
                              context.theme.canvasColor.withValues(alpha: 0.9),
                            ],
                          )
                        : null,
                  ),
                  child: ServerImage(imageUrl: manga.thumbnailUrl ?? ""),
                )
              : SizedBox(
                  height: context.height * .3,
                  child: ImageIcon(
                    AssetImage(Assets.icons.darkIcon.path),
                    size: context.height * .2,
                  ),
                ),
        );
  }
}
