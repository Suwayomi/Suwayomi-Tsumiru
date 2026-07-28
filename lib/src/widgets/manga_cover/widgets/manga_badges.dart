// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../constants/app_sizes.dart';
import '../../../constants/enum.dart';
import '../../../features/manga_book/domain/manga/manga_model.dart';
import '../../../features/offline/data/offline_download_providers.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/misc/language_flag.dart';
import '../../../utils/theme/brand.dart';
import '../../server_image.dart';
import '../providers/manga_cover_providers.dart';

/// How far each segment of a combined badge slides under its predecessor, and
/// the width of the diagonal cut between them.
const double _kBadgeSlant = 6;

/// Corner rounding, matching the app's other badge chips.
const double _kBadgeRadius = 8;

/// The flag emoji's font size as a share of the strip height. Doubles as the
/// line-height multiplier's inverse, so the emoji's line box is exactly one
/// strip tall — see the language segment.
const double _kFlagFontRatio = .7;

/// Strip height, tracking the platform text scale but capped at 1.4× so a large
/// font can't clip a three-digit count nor swallow the cover.
double _stripHeight(BuildContext context) {
  final ratio =
      (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(1.0, 1.4);
  return 20 * ratio;
}

/// One cell of a badge strip. [fill] segments own their whole cell (no content
/// padding, no slant inset) — for artwork that should bleed to the diagonal.
typedef _Segment = ({Decoration decoration, Widget child, bool fill});

/// Badge corners are physical: the layout editor offers "top-left" and
/// "top-right", not "start" and "end". Every row that places a cluster pins
/// this, or an RTL locale mirrors the clusters onto the wrong corners.
const _kPhysical = TextDirection.ltr;

class MangaBadgesRow extends ConsumerWidget {
  const MangaBadgesRow({
    super.key,
    required this.manga,
    this.showCountBadges = false,
    this.padding,
  });
  final MangaDto manga;

  /// Library covers (true) get the user's configurable badge set; Browse and
  /// global-search covers (false) get only the "already in library" marker.
  final bool showCountBadges;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.theme.colorScheme;
    final height = _stripHeight(context);

    if (!showCountBadges) {
      if (!manga.inLibrary.ifNull()) return const SizedBox.shrink();
      return Padding(
        padding: padding ?? KEdgeInsets.a8.size,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          textDirection: _kPhysical,
          children: [
            _BadgeStrip(
              height: height,
              side: BadgeSide.left,
              segments: [
                _iconSegment(
                  Icons.collections_bookmark_rounded,
                  scheme.primary,
                  scheme.onPrimary,
                  height,
                ),
              ],
            ),
          ],
        ),
      );
    }

    final layout = ref.watch(libraryBadgeLayoutProvider);
    final unreadMode =
        ref.watch(unreadBadgeStyleProvider) ?? UnreadBadgeMode.count;
    final downloadedBadge = ref.watch(downloadedBadgeProvider).ifNull(true);
    final languageBadge = ref.watch(languageBadgeProvider).ifNull(false);
    final sourceBadge = ref.watch(sourceBadgeProvider).ifNull(false);
    // At least one chapter downloaded to THIS device, a subset of the server's.
    // Empty set when on-device storage is unavailable, so the badge self-hides.
    final onDevice = ref.watch(onDeviceBadgeProvider).ifNull(true) &&
        (ref.watch(offlineDeviceMangaIdsProvider).value ?? const <int>{})
            .contains(manga.id);

    final source = manga.source;
    final isLocal = source?.lang == kLocalSourceLang;
    final langCode = source?.lang;
    final langFlag = isLocal ? null : languageFlagEmoji(langCode);

    // The segment for [badge], or null when it's off or this manga has nothing
    // to show for it.
    _Segment? segmentFor(LibraryBadge badge) {
      switch (badge) {
        case LibraryBadge.unread:
          if (!unreadMode.isVisible || !manga.unreadCount.isGreaterThan(0)) {
            return null;
          }
          return unreadMode == UnreadBadgeMode.dot
              ? _plainSegment(scheme.primary, height)
              : _textSegment(
                  '${manga.unreadCount.getValueOnNullOrNegative()}',
                  scheme.primary,
                  scheme.onPrimary,
                );
        case LibraryBadge.downloaded:
          if (!downloadedBadge || !manga.downloadCount.isGreaterThan(0)) {
            return null;
          }
          return _textSegment(
            '${manga.downloadCount.getValueOnNullOrNegative()}',
            scheme.tertiary,
            scheme.onTertiary,
          );
        case LibraryBadge.onDevice:
          if (!onDevice) return null;
          // Brand gradient + downloaded pin, distinct from the flat
          // server-download count.
          return (
            decoration: BoxDecoration(gradient: brandGradient(scheme)),
            child: Icon(
              Icons.offline_pin_rounded,
              color: onBrandGradient,
              size: height * .8,
            ),
            fill: false,
          );
        case LibraryBadge.language:
          if (!languageBadge || langCode == null || isLocal) return null;
          // Emoji carry their own colour, so the flag sits on the surface tone
          // instead of an accent fill. Unmapped codes fall back to the code.
          return langFlag != null
              ? (
                  decoration: BoxDecoration(color: scheme.surface),
                  child: Text(
                    langFlag,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: height * _kFlagFontRatio,
                      // Line box = exactly one strip, which bounds the emoji's
                      // line spacing without squeezing it: a 1em box is shorter
                      // than the font's ascent+descent, and shifted the glyph
                      // ~1px above the strip's centre line.
                      height: 1 / _kFlagFontRatio,
                      // Trim any remaining overflow top and bottom equally,
                      // not by the font's lopsided ascent:descent ratio.
                      leadingDistribution: TextLeadingDistribution.even,
                    ),
                  ),
                  fill: false,
                )
              : _textSegment(
                  langCode.toUpperCase(),
                  scheme.secondary,
                  scheme.onSecondary,
                );
        case LibraryBadge.source:
          if (!sourceBadge || source == null) return null;
          // Local Source has no extension icon to fetch, so it gets a folder
          // glyph — what the separate `localBadge` used to draw.
          return isLocal
              ? _iconSegment(
                  Icons.folder_rounded,
                  scheme.secondary,
                  scheme.onSecondary,
                  height,
                )
              : (
                  decoration: BoxDecoration(color: scheme.surface),
                  child:
                      _SourceIcon(iconUrl: source.iconUrl, size: height * .8),
                  fill: false,
                );
      }
    }

    final left = <_Segment>[];
    final right = <_Segment>[];
    for (final placement in layout) {
      final segment = segmentFor(placement.badge);
      if (segment == null) continue;
      (placement.side == BadgeSide.left ? left : right).add(segment);
    }
    if (left.isEmpty && right.isEmpty) return const SizedBox.shrink();

    final leftStrip =
        _BadgeStrip(segments: left, side: BadgeSide.left, height: height);
    final rightStrip =
        _BadgeStrip(segments: right, side: BadgeSide.right, height: height);

    return Padding(
      padding: padding ?? KEdgeInsets.a8.size,
      // Reaching the cover's right edge needs a bounded width, which the list
      // tiles don't provide (their Row lays non-flex children out unbounded);
      // fall back to a min-width row there.
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (!constraints.hasBoundedWidth) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              textDirection: _kPhysical,
              children: [
                if (left.isNotEmpty) leftStrip,
                if (left.isNotEmpty && right.isNotEmpty)
                  const SizedBox(width: 4),
                if (right.isNotEmpty) rightStrip,
              ],
            );
          }
          // Flexible, not a Spacer between two intrinsic strips: with every
          // badge on, a narrow cell's two clusters together overflow the cover.
          // Capping each at half the width lets its own clip shave the excess.
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            textDirection: _kPhysical,
            children: [
              Flexible(
                child: left.isEmpty ? const SizedBox.shrink() : leftStrip,
              ),
              Flexible(
                child: right.isEmpty ? const SizedBox.shrink() : rightStrip,
              ),
            ],
          );
        },
      ),
    );
  }
}

_Segment _textSegment(String text, Color background, Color foreground) => (
      decoration: BoxDecoration(color: background),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: foreground, fontSize: 12, height: 1),
      ),
      fill: false,
    );

_Segment _iconSegment(
  IconData icon,
  Color background,
  Color foreground,
  double height,
) =>
    (
      decoration: BoxDecoration(color: background),
      child: Icon(icon, color: foreground, size: height * .8),
      fill: false,
    );

/// "There is something unread" without the arithmetic: a blank accent chip.
_Segment _plainSegment(Color background, double height) => (
      decoration: BoxDecoration(color: background),
      child: SizedBox(width: height * .3),
      fill: false,
    );

/// A cluster of badges pinned to one corner of a cover.
///
/// A lone badge is a plain rounded square. Two or more combine: each segment
/// after the first gets a diagonal leading edge and slides [_kBadgeSlant] under
/// its predecessor, so the seam reads as one continuous cut. The strip keeps
/// [_kBadgeRadius] on every corner either way.
class _BadgeStrip extends StatelessWidget {
  const _BadgeStrip({
    required this.segments,
    required this.side,
    required this.height,
  });

  final List<_Segment> segments;
  final BadgeSide side;
  final double height;

  /// Right-hand clusters mirror the geometry so the diagonal leans toward its
  /// own corner instead of away from it.
  bool get _mirrored => side == BadgeSide.right;

  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) return const SizedBox.shrink();

    if (segments.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(_kBadgeRadius),
        // Same tight height [_OverlappingRow] gives multi-segment cells, so a
        // lone badge doesn't resize the moment a second one joins it.
        child: SizedBox(
          height: height,
          child: _cell(segments.single, isFirst: true, isLast: true),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(_kBadgeRadius),
      child: _OverlappingRow(
        overlap: _kBadgeSlant,
        height: height,
        children: [
          for (var i = 0; i < segments.length; i++)
            // Only segments after the first are clipped: each paints over its
            // predecessor's trailing edge, and the clip makes that a seam.
            i == 0
                ? _cell(segments[i], isFirst: true, isLast: false)
                : ClipPath(
                    clipper: _SlantClipper(
                      slant: _kBadgeSlant,
                      mirrored: _mirrored,
                    ),
                    child: _cell(
                      segments[i],
                      isFirst: false,
                      isLast: i == segments.length - 1,
                    ),
                  ),
        ],
      ),
    );
  }

  /// One segment box. Structural padding keeps content clear of the diagonal:
  /// the leading `slant` on every non-first segment (its own cut) and the
  /// trailing `slant` on every non-last one (the next segment overlaps it).
  Widget _cell(
    _Segment segment, {
    required bool isFirst,
    required bool isLast,
  }) {
    final content = segment.fill ? 0.0 : 4.0;
    return DecoratedBox(
      decoration: segment.decoration,
      child: Padding(
        padding: EdgeInsets.only(
          left: (isFirst || segment.fill ? 0.0 : _kBadgeSlant) +
              (segment.fill ? 0.0 : content + (isFirst ? 2 : 0)),
          right: (isLast || segment.fill ? 0.0 : _kBadgeSlant) +
              (segment.fill ? 0.0 : content + (isLast ? 2 : 0)),
        ),
        child: Center(
          widthFactor: 1,
          child: segment.child,
        ),
      ),
    );
  }
}

/// Clips a segment's leading edge into a diagonal. Unmirrored cuts the TOP-left
/// corner, so the seam leans "/"; mirrored cuts the BOTTOM-left corner ("\")
/// for right-hand clusters.
class _SlantClipper extends CustomClipper<Path> {
  const _SlantClipper({required this.slant, required this.mirrored});
  final double slant;
  final bool mirrored;

  @override
  Path getClip(Size size) {
    final path = Path();
    if (mirrored) {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width, size.height)
        ..lineTo(slant, size.height);
    } else {
      path
        ..moveTo(slant, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height);
    }
    return path..close();
  }

  @override
  bool shouldReclip(_SlantClipper old) =>
      old.slant != slant || old.mirrored != mirrored;
}

/// A row whose children overlap by [overlap] logical pixels — [Row] rejects
/// negative spacing. Children lay out at a tight [height] and paint in order,
/// so each clipped segment covers its predecessor's trailing edge.
class _OverlappingRow extends MultiChildRenderObjectWidget {
  const _OverlappingRow({
    required this.overlap,
    required this.height,
    required super.children,
  });

  final double overlap;
  final double height;

  @override
  _RenderOverlappingRow createRenderObject(BuildContext context) =>
      _RenderOverlappingRow(overlap: overlap, stripHeight: height);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderOverlappingRow renderObject,
  ) {
    renderObject
      ..overlap = overlap
      ..stripHeight = height;
  }
}

class _OverlapParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderOverlappingRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _OverlapParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _OverlapParentData> {
  _RenderOverlappingRow({
    required double overlap,
    required double stripHeight,
  })  : _overlap = overlap,
        _stripHeight = stripHeight;

  double _overlap;
  double get overlap => _overlap;
  set overlap(double value) {
    if (_overlap == value) return;
    _overlap = value;
    markNeedsLayout();
  }

  double _stripHeight;
  double get stripHeight => _stripHeight;
  set stripHeight(double value) {
    if (_stripHeight == value) return;
    _stripHeight = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _OverlapParentData) {
      child.parentData = _OverlapParentData();
    }
  }

  @override
  void performLayout() {
    // Each segment sizes itself horizontally and is stretched to the strip
    // height, so the diagonals line up across the whole cluster.
    final childConstraints = BoxConstraints.tightFor(height: stripHeight);
    var x = 0.0;
    var child = firstChild;
    while (child != null) {
      child.layout(childConstraints, parentUsesSize: true);
      (child.parentData! as _OverlapParentData).offset = Offset(x, 0);
      x += child.size.width - overlap;
      child = childAfter(child);
    }
    // The last child contributes its FULL width — only the seams shrink.
    final width = childCount == 0 ? 0.0 : x + overlap;
    size = constraints.constrain(Size(width, stripHeight));
  }

  @override
  double computeMinIntrinsicHeight(double width) => stripHeight;

  @override
  double computeMaxIntrinsicHeight(double width) => stripHeight;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
}

/// A source icon fetched from the server, sized to the badge strip.
///
/// [ServerImage]'s stock placeholder and failure glyph are scaled for a
/// full-page image, so both are pinned to the cell here: [IconTheme] caps the
/// unsized fallback icon, and the placeholder occupies exactly [size] so the
/// strip's width doesn't jump when the real icon arrives.
class _SourceIcon extends StatelessWidget {
  const _SourceIcon({required this.iconUrl, required this.size});
  final String iconUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = context.theme.colorScheme;
    return SizedBox.square(
      dimension: size,
      child: IconTheme.merge(
        data: IconThemeData(size: size, color: scheme.onSurfaceVariant),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(size * .2),
          child: ServerImage(
            imageUrl: iconUrl,
            size: Size.square(size),
            // Extension icons are not all square. `cover` (ServerImage's
            // default) crops them to the cell; `contain` fits the whole glyph.
            fit: BoxFit.contain,
            progressIndicatorBuilder: (_, __, ___) => Center(
              child: Icon(Icons.extension_rounded, size: size * .8),
            ),
          ),
        ),
      ),
    );
  }
}

class MangaBadge extends StatelessWidget {
  const MangaBadge({
    super.key,
    this.text,
    this.icon,
    required this.color,
    required this.textColor,
    this.side = BadgeSide.left,
  }) : assert(text != null || icon != null);

  final String? text;
  final IconData? icon;
  final Color color;
  final Color textColor;

  /// Which corner the badge sits in. A lone badge looks the same either way;
  /// it's here so callers describe placement as [MangaBadgesRow] does.
  final BadgeSide side;

  @override
  Widget build(BuildContext context) {
    final height = _stripHeight(context);
    return _BadgeStrip(
      height: height,
      side: side,
      segments: [
        text.isNotBlank
            ? _textSegment(text!, color, textColor)
            : _iconSegment(icon!, color, textColor, height),
      ],
    );
  }
}
