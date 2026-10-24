// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
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

const double _kBadgeSlant = 6;

const double _kBadgeRadius = 8;

/// Inverse line-height multiplier keeps the emoji line box exactly one strip tall.
const double _kFlagFontRatio = .7;

double _stripHeight(BuildContext context) {
  final ratio = (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(
    1.0,
    1.4,
  );
  return 20 * ratio;
}

/// Fill segments have no padding/slant inset so artwork reaches the diagonal.
typedef _Segment = ({Decoration decoration, Widget child, bool fill});

/// Badge corners are physical; pin direction so RTL locales cannot mirror clusters.
const _kPhysical = TextDirection.ltr;

class MangaBadgesRow extends ConsumerWidget {
  const MangaBadgesRow({
    super.key,
    required this.manga,
    this.showCountBadges = false,
    this.padding,
  });
  final MangaDto manga;

  /// False shows only the library marker; true uses the configured library badge set.
  final bool showCountBadges;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.theme.colorScheme;
    final height = _stripHeight(context);

    if (!showCountBadges) {
      if (!manga.user.inLibrary.ifNull()) return const SizedBox.shrink();
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
                  FluentIcons.library_24_regular,
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
    final onDevice =
        ref.watch(onDeviceBadgeProvider).ifNull(true) &&
        (ref.watch(offlineDeviceMangaIdsProvider).value ?? const <int>{})
            .contains(manga.id);

    final source = manga.source;
    final isLocal = source?.lang == kLocalSourceLang;
    final langCode = source?.lang;
    final langFlag = isLocal ? null : languageFlagEmoji(langCode);

    _Segment? segmentFor(LibraryBadge badge) {
      switch (badge) {
        case LibraryBadge.unread:
          if (!unreadMode.isVisible ||
              !manga.user.unreadCount.isGreaterThan(0)) {
            return null;
          }
          return unreadMode == UnreadBadgeMode.dot
              ? _plainSegment(scheme.primary, height)
              : _textSegment(
                  '${manga.user.unreadCount.getValueOnNullOrNegative()}',
                  scheme.primary,
                  scheme.onPrimary,
                );
        case LibraryBadge.downloaded:
          if (!downloadedBadge || !manga.user.downloadCount.isGreaterThan(0)) {
            return null;
          }
          return _textSegment(
            '${manga.user.downloadCount.getValueOnNullOrNegative()}',
            scheme.tertiary,
            scheme.onTertiary,
          );
        case LibraryBadge.onDevice:
          if (!onDevice) return null;
          final brand = BrandColors.of(context);
          return (
            decoration: BoxDecoration(gradient: brand.gradient),
            child: Icon(
              FluentIcons.checkmark_circle_24_filled,
              color: brand.onGradient,
              size: height * .8,
            ),
            fill: false,
          );
        case LibraryBadge.language:
          if (!languageBadge || langCode == null || isLocal) return null;
          return langFlag != null
              ? (
                  decoration: BoxDecoration(color: scheme.surface),
                  child: Text(
                    langFlag,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: height * _kFlagFontRatio,
                      // A full-strip line box avoids emoji font ascent/descent shifting the glyph.
                      height: 1 / _kFlagFontRatio,
                      // Trim overflow symmetrically instead of using the font ascent/descent ratio.
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
          // Local Source has no extension icon to fetch.
          return isLocal
              ? _iconSegment(
                  FluentIcons.folder_24_regular,
                  scheme.secondary,
                  scheme.onSecondary,
                  height,
                )
              : (
                  decoration: BoxDecoration(color: scheme.surface),
                  child: _SourceIcon(
                    iconUrl: source.iconUrl,
                    size: height * .8,
                  ),
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

    final leftStrip = _BadgeStrip(
      segments: left,
      side: BadgeSide.left,
      height: height,
    );
    final rightStrip = _BadgeStrip(
      segments: right,
      side: BadgeSide.right,
      height: height,
    );

    return Padding(
      padding: padding ?? KEdgeInsets.a8.size,
      // List rows provide unbounded width; fall back to a min-width badge row.
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
          // Cap each cluster at half the cover width so clipping handles narrow cells.
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
) => (
  decoration: BoxDecoration(color: background),
  child: Icon(icon, color: foreground, size: height * .8),
  fill: false,
);

_Segment _plainSegment(Color background, double height) => (
  decoration: BoxDecoration(color: background),
  child: SizedBox(width: height * .3),
  fill: false,
);

class _BadgeStrip extends StatelessWidget {
  const _BadgeStrip({
    required this.segments,
    required this.side,
    required this.height,
  });

  final List<_Segment> segments;
  final BadgeSide side;
  final double height;

  /// Mirror diagonals toward the right-hand corner.
  bool get _mirrored => side == BadgeSide.right;

  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) return const SizedBox.shrink();

    if (segments.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(_kBadgeRadius),
        // Keep single badges the same height as multi-segment cells.
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

  /// Reserve leading slant for this cut and trailing slant for the next overlap.
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
          left:
              (isFirst || segment.fill ? 0.0 : _kBadgeSlant) +
              (segment.fill ? 0.0 : content + (isFirst ? 2 : 0)),
          right:
              (isLast || segment.fill ? 0.0 : _kBadgeSlant) +
              (segment.fill ? 0.0 : content + (isLast ? 2 : 0)),
        ),
        child: Center(widthFactor: 1, child: segment.child),
      ),
    );
  }
}

/// Unmirrored cuts top-left (/); mirrored cuts bottom-left (\).
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

/// Row rejects negative spacing; overlap children at a tight height in paint order.
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
  _RenderOverlappingRow({required double overlap, required double stripHeight})
    : _overlap = overlap,
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
    final childConstraints = BoxConstraints.tightFor(height: stripHeight);
    var x = 0.0;
    var child = firstChild;
    while (child != null) {
      child.layout(childConstraints, parentUsesSize: true);
      (child.parentData! as _OverlapParentData).offset = Offset(x, 0);
      x += child.size.width - overlap;
      child = childAfter(child);
    }
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

/// Bound placeholder/error glyphs to the strip size so loading cannot change badge width.
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
            // Contain non-square extension icons so the full glyph remains visible.
            fit: BoxFit.contain,
            progressIndicatorBuilder: (_, _, _) =>
                Center(child: Icon(FluentIcons.puzzle_piece_24_regular, size: size)),
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
