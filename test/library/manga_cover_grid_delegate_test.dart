// Covers are 2:3 (Komikku's MangaCover.Book). The regression these guard
// against: deriving the cover from a fixed cell ratio, which cropped the art
// and — with the title block below — drifted as the columns got narrower.

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/app_sizes.dart';

SliverConstraints _constraints(double crossAxisExtent) => SliverConstraints(
  axisDirection: AxisDirection.down,
  growthDirection: GrowthDirection.forward,
  userScrollDirection: ScrollDirection.idle,
  scrollOffset: 0,
  precedingScrollExtent: 0,
  overlap: 0,
  remainingPaintExtent: 1000,
  crossAxisExtent: crossAxisExtent,
  crossAxisDirection: AxisDirection.right,
  viewportMainAxisExtent: 1000,
  remainingCacheExtent: 1000,
  cacheOrigin: 0,
);

/// Ratio of the artwork as it actually renders: the cell minus the title block
/// and minus the card margin that insets the image inside the cell. Measuring
/// the cell alone would pass while every cover on screen was still wrong.
double _coverRatio(
  SliverGridLayout layout, {
  double titleExtent = 0,
  double coverInset = kMangaCoverCardInset,
}) {
  final tile = layout as SliverGridRegularTileLayout;
  return (tile.childCrossAxisExtent - coverInset) /
      (tile.childMainAxisExtent - titleExtent - coverInset);
}

void main() {
  group('cover-only and overlay grids', () {
    test('cover is 2:3 at every viewport width', () {
      for (final width in [320.0, 411.0, 600.0, 1280.0, 1920.0]) {
        const delegate = MangaCoverGridDelegate(
          maxCrossAxisExtent: 180,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2,
        );
        final layout = delegate.getLayout(_constraints(width));
        expect(
          _coverRatio(layout),
          closeTo(kMangaCoverAspectRatio, 0.0001),
          reason: 'viewport ${width}px',
        );
      }
    });
  });
}
