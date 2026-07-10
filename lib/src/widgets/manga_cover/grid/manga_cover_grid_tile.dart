// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../constants/app_sizes.dart';
import '../../../constants/gen/assets.gen.dart';
import '../../../features/manga_book/domain/manga/manga_model.dart';
import '../../../features/manga_book/presentation/manga_thumbnail_viewer/manga_thumbnail_viewer.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../server_image.dart';
import '../providers/manga_cover_providers.dart';
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
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _CoverReadProgressBar(manga: manga),
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
                    // Drawn on the cover art, not the theme surface: always
                    // white over the black scrim, shadowed for light covers
                    // (Komikku's CoverTextOverlay values).
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      height: 1.5,
                      shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                    ),
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
                    // Theme-independent scrim (Komikku: transparent → 67%
                    // black over the bottom third) — the title always reads
                    // white-on-dark in both light and dark mode.
                    gradient: showTitle
                        ? const LinearGradient(
                            begin: Alignment(0, 1 / 3),
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Color(0xAA000000),
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

/// Fraction (0..1] of a series that's been read, or null when there's nothing
/// to show (no chapters, or none read yet). Clamps defensively so odd counts
/// (unread > total) never produce an out-of-range or negative bar.
double? coverReadFraction({required int totalChapters, required int unreadCount}) {
  if (totalChapters <= 0) return null;
  final read = (totalChapters - unreadCount).clamp(0, totalChapters);
  return read <= 0 ? null : read / totalChapters;
}

/// Thin read-progress bar along the bottom edge of a library cover, gated on the
/// per-user toggle. Percent read is derived client-side from the manga's own
/// counts, so it needs no server call.
class _CoverReadProgressBar extends ConsumerWidget {
  const _CoverReadProgressBar({required this.manga});

  final MangaDto manga;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(readProgressBarProvider).ifNull()) {
      return const SizedBox.shrink();
    }
    final fraction = coverReadFraction(
      totalChapters: manga.chapters.totalCount,
      unreadCount: manga.unreadCount.getValueOnNullOrNegative(),
    );
    if (fraction == null) return const SizedBox.shrink();
    return LinearProgressIndicator(
      value: fraction,
      minHeight: 3,
      backgroundColor: Colors.black.withValues(alpha: 0.35),
      valueColor: AlwaysStoppedAnimation(context.theme.colorScheme.primary),
    );
  }
}
