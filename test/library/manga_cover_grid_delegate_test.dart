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

/// Ratio of the cover itself, with the title block (if any) taken back off.
double _coverRatio(SliverGridLayout layout, {double titleExtent = 0}) {
  final tile = layout as SliverGridRegularTileLayout;
  return tile.childCrossAxisExtent /
      (tile.childMainAxisExtent - titleExtent);
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

    test('cover is 2:3 at every fixed column count', () {
      for (final columns in [1, 2, 3, 5, 8]) {
        final delegate = MangaCoverFixedCountGridDelegate(
          crossAxisCount: columns,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2,
        );
        final layout = delegate.getLayout(_constraints(411));
        expect(
          _coverRatio(layout),
          closeTo(kMangaCoverAspectRatio, 0.0001),
          reason: '$columns columns',
        );
      }
    });
  });

  group('comfortable grid (title below)', () {
    test('title block is added on top of a 2:3 cover, not taken out of it', () {
      for (final columns in [2, 3, 4, 6]) {
        final delegate = MangaCoverFixedCountGridDelegate(
          crossAxisCount: columns,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2,
          titleExtent: kGridTitleExtent,
        );
        final layout = delegate.getLayout(_constraints(411));
        expect(
          _coverRatio(layout, titleExtent: kGridTitleExtent),
          closeTo(kMangaCoverAspectRatio, 0.0001),
          reason: '$columns columns',
        );
      }
    });

    test('cell is exactly the title block taller than the cover-only cell', () {
      final bare = const MangaCoverFixedCountGridDelegate(crossAxisCount: 3)
          .getLayout(_constraints(411)) as SliverGridRegularTileLayout;
      final withTitle = const MangaCoverFixedCountGridDelegate(
        crossAxisCount: 3,
        titleExtent: kGridTitleExtent,
      ).getLayout(_constraints(411)) as SliverGridRegularTileLayout;

      expect(
        withTitle.childMainAxisExtent - bare.childMainAxisExtent,
        closeTo(kGridTitleExtent, 0.0001),
      );
      expect(withTitle.childCrossAxisExtent, bare.childCrossAxisExtent);
    });
  });
}
