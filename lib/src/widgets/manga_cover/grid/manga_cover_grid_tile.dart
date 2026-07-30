// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../constants/app_sizes.dart';
import '../../../constants/enum.dart';
import '../../../constants/gen/assets.gen.dart';
import '../../../features/manga_book/domain/manga/manga_model.dart';
import '../../../features/manga_book/presentation/manga_thumbnail_viewer/manga_thumbnail_viewer.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../custom_circular_progress_indicator.dart';
import '../../server_image.dart';
import '../providers/manga_cover_providers.dart';
import '../widgets/continue_reading_button.dart';
import '../widgets/manga_badges.dart';

/// The 2:3 "book" ratio a uniform cover cell uses — also what the freeform
/// styles reserve until the real cover ratio is known.
const double _kBookAspectRatio = 2 / 3;

/// Freeform cover height clamp, as a multiple of the tile width: a ceiling so a
/// long-strip cover can't run off the screen, and a floor so a freak wide cover
/// can't collapse the tile.
const double _kFreeformMinHeightFactor = 1.0;
const double _kFreeformMaxHeightFactor = 10 / 3;

/// Comfortable-grid title metrics (Komikku's values): 12sp over an 18px line,
/// 4dp of padding all round.
const double _kTitleFontSize = 12;
const double _kTitleLineFactor = 1.5;
const double _kTitlePadding = 4;

/// Share of a uniform cell the title block may never exceed, so the cell can't
/// overflow at extreme text scales.
const double _kMaxTitleShare = .45;

/// Height of a [maxLines]-line title block at the current platform text scale.
double _titleBlockHeight(BuildContext context, int maxLines) =>
    MediaQuery.textScalerOf(context).scale(_kTitleFontSize) *
            _kTitleLineFactor *
            maxLines +
        _kTitlePadding * 2;

class MangaCoverGridTile extends StatelessWidget {
  const MangaCoverGridTile({
    super.key,
    required this.manga,
    this.onPressed,
    this.onLongPress,
    this.onContinueReading,
    this.showTitle = true,
    this.titleBelow = false,
    this.showBadges = true,
    this.showCountBadges = false,
    this.showDarkOverlay = true,
    this.selected = false,
    this.gridStyle = LibraryGridStyle.uniform,
    this.outlineOnCovers = false,
    this.limitTitleLines = true,
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

  /// Comfortable grid: the title renders under the cover on the theme surface
  /// instead of overlaid on the art ([showTitle] is ignored for the overlay).
  final bool titleBelow;
  final bool showBadges;
  final bool showDarkOverlay;

  /// Multi-select highlight: a primary-tinted border + check on the
  /// library selection.
  final bool selected;

  /// Cover geometry. [LibraryGridStyle.uniform] (the default, and what Browse
  /// uses) fills the cell it is given; the freeform styles size the tile from
  /// the cover art instead — see [_cover].
  final LibraryGridStyle gridStyle;

  /// A hairline border around the cover so pale art still reads as a card.
  /// Passed in rather than read from [outlineOnCoversProvider] so this shared
  /// tile stays usable outside the library. The selection border wins while
  /// [selected].
  final bool outlineOnCovers;

  /// Cap the below-cover title at two ellipsized lines. When false it takes the
  /// whole title slot (see [_kMaxTitleShare]).
  final bool limitTitleLines;

  bool get _overlayTitle => showTitle && !titleBelow;

  @override
  Widget build(BuildContext context) {
    final freeform = gridStyle.isFreeform;
    final card = _card(context, outline: outlineOnCovers, freeform: freeform);
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
      child: freeform
          // The tile's height comes from the cover, so nothing may stretch.
          // Non-uniform bottom-aligns: the aligned grid stretches a row's tiles
          // to its tallest, so `end` gives the flush baseline.
          ? Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: gridStyle == LibraryGridStyle.nonUniform
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                card,
                if (titleBelow)
                  _TitleBlock(
                    title: manga.title,
                    limitLines: limitTitleLines,
                  ),
              ],
            )
          : titleBelow
              // Uniform + title below: the cover flexes and the title takes a
              // fixed block, so every cover in a row ends up the same height.
              ? LayoutBuilder(
                  builder: (context, constraints) {
                    final twoLines = _titleBlockHeight(context, 2);
                    final cap = constraints.hasBoundedHeight
                        ? constraints.maxHeight * _kMaxTitleShare
                        : twoLines;
                    final blockHeight =
                        limitTitleLines ? min(twoLines, cap) : cap;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: card),
                        SizedBox(
                          height: blockHeight,
                          child: _TitleBlock(
                            title: manga.title,
                            limitLines: limitTitleLines,
                          ),
                        ),
                      ],
                    );
                  },
                )
              : card,
    );
  }

  Widget _card(
    BuildContext context, {
    required bool outline,
    required bool freeform,
  }) {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: KBorderRadius.r12.radius,
        side: selected
            ? BorderSide(color: context.theme.colorScheme.primary, width: 3)
            : outline
                ? BorderSide(
                    color: context.theme.colorScheme.outlineVariant,
                    width: 1,
                  )
                : BorderSide.none,
      ),
      // A flat Stack, not a GridTile: GridTile lays its child out with
      // Positioned.fill, which leaves the Stack nothing to size itself from —
      // and the freeform styles need it to size to the cover.
      child: Stack(
        // Uniform passes the cell's tight constraints straight to the cover;
        // freeform loosens them so the cover's clamped height sizes the stack.
        fit: freeform ? StackFit.loose : StackFit.passthrough,
        children: [
          _cover(context, freeform: freeform),
          if (_overlayTitle)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _overlayTitleBar(context),
            ),
          if (showBadges)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: MangaBadgesRow(
                manga: manga,
                showCountBadges: showCountBadges,
              ),
            ),
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
          // No title to flow beside (cover-only, title-below, or the
          // descriptive-list cover): overlay the button on the cover corner.
          // With an overlaid title, the button lives in the footer row
          // instead so it can't cover the text.
          if (onContinueReading != null && !selected && !_overlayTitle)
            Positioned(
              right: 6,
              bottom: 6,
              child: ContinueReadingButton(onPressed: onContinueReading!),
            ),
          if (showBadges)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _CoverReadProgressBar(manga: manga),
            ),
        ],
      ),
    );
  }

  Widget _overlayTitleBar(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        dense: true,
        title: Text(
          manga.title,
          overflow: TextOverflow.ellipsis,
          maxLines: 2,
          // Drawn on the cover art, not the theme surface: always white over
          // the black scrim, shadowed for light covers (Komikku's
          // CoverTextOverlay values).
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            height: 1.5,
            shadows: [Shadow(color: Colors.black, blurRadius: 4)],
          ),
        ),
        // The button shares the footer row: the title takes the remaining
        // width, so it can never sit under the button.
        trailing: onContinueReading != null
            ? ContinueReadingButton(
                onPressed: onContinueReading!,
                size: 28,
                iconSize: 16,
              )
            : null,
      );

  Widget _cover(BuildContext context, {required bool freeform}) {
    if (manga.thumbnailUrl.isBlank) {
      final fallback = ImageIcon(
        AssetImage(Assets.icons.darkIcon.path),
        size: context.height * .2,
      );
      return freeform
          // No art to measure: reserve the book ratio so the tile lines up with
          // its neighbours instead of claiming a screen-relative slab.
          ? AspectRatio(
              aspectRatio: _kBookAspectRatio,
              child: FittedBox(fit: BoxFit.scaleDown, child: fallback),
            )
          : SizedBox(height: context.height * .3, child: fallback);
    }

    final Widget image = Container(
      foregroundDecoration: BoxDecoration(
        border: Border.all(
          width: 0,
          color: context.theme.canvasColor,
        ),
        boxShadow: showDarkOverlay
            ? [
                BoxShadow(
                  color: context.theme.canvasColor.withValues(alpha: .5),
                )
              ]
            : null,
        // Theme-independent scrim (Komikku: transparent → 67% black over the
        // bottom third) — the title always reads white-on-dark in both light
        // and dark mode.
        gradient: _overlayTitle
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
      // Decode at tile size, not source size: full-res covers overflow
      // Flutter's decoded-image budget after a few dozen tiles, so every tab
      // switch re-decoded (and re-shimmered) the whole grid.
      child: LayoutBuilder(
        builder: (context, constraints) => ServerImage(
          imageUrl: manga.thumbnailUrl ?? "",
          memCacheWidth: constraints.hasBoundedWidth
              ? (constraints.maxWidth *
                      MediaQuery.devicePixelRatioOf(context))
                  .round()
                  .clamp(1, 1 << 16)
              : null,
          // A freeform tile is only as tall as its cover, so a screen-relative
          // shimmer would make the grid lurch once the art lands.
          progressIndicatorBuilder: freeform
              ? (context, url, progress) => const _FreeformCoverPlaceholder()
              : null,
        ),
      ),
    );
    if (!freeform) return image;

    // The stack loosened both axes, so pin the width back to the column width;
    // only the height is allowed to follow the art.
    return SizedBox(
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width =
              constraints.maxWidth.isFinite ? constraints.maxWidth : 0.0;
          return ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: width * _kFreeformMinHeightFactor,
              maxHeight: width * _kFreeformMaxHeightFactor,
            ),
            child: image,
          );
        },
      ),
    );
  }
}

/// The comfortable-grid title drawn under the cover, on the theme surface.
///
/// With [limitLines] on it is a two-line ellipsized block. With it off it wraps
/// in full wherever the tile can grow; in a fixed-height uniform cell the line
/// cap comes from the granted height instead, so the text stops on a line
/// boundary.
class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.title, required this.limitLines});

  final String title;
  final bool limitLines;

  static const _style = TextStyle(
    fontSize: _kTitleFontSize,
    height: _kTitleLineFactor,
  );

  /// Skia collapses `ellipsis + maxLines: null` to one line, so uncapped text
  /// has to ask to wrap rather than to ellipsize.
  static Widget _text(String title, int? maxLines) => Text(
        title,
        maxLines: maxLines,
        softWrap: true,
        overflow:
            maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis,
        style: _style,
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(_kTitlePadding),
      child: limitLines
          ? _text(title, 2)
          : LayoutBuilder(
              builder: (context, constraints) {
                if (!constraints.hasBoundedHeight) {
                  // Self-sizing tile: let the whole title through.
                  return _text(title, null);
                }
                final lineHeight =
                    MediaQuery.textScalerOf(context).scale(_kTitleFontSize) *
                        _kTitleLineFactor;
                return _text(
                  title,
                  max(1, (constraints.maxHeight / lineHeight).floor()),
                );
              },
            ),
    );
  }
}

/// Holds the 2:3 book ratio while the real cover ratio is unknown, so a
/// freeform tile barely moves once the art decodes.
class _FreeformCoverPlaceholder extends StatelessWidget {
  const _FreeformCoverPlaceholder();

  @override
  Widget build(BuildContext context) => const AspectRatio(
        aspectRatio: _kBookAspectRatio,
        child: Center(child: SorayomiShimmerIndicator()),
      );
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
