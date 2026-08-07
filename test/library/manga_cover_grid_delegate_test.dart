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

  group('card-less grid (recommendations)', () {
    test('cover is 2:3 with a title below and no card to compensate for', () {
      for (final width in [320.0, 411.0, 800.0]) {
        const delegate = MangaCoverGridDelegate(
          maxCrossAxisExtent: 120,
          titleExtent: kRecommendsTitleExtent,
          coverInset: 0,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        );
        final layout = delegate.getLayout(_constraints(width));
        expect(
          _coverRatio(
            layout,
            titleExtent: kRecommendsTitleExtent,
            coverInset: 0,
          ),
          closeTo(kMangaCoverAspectRatio, 0.0001),
          reason: 'viewport ${width}px',
        );
      }
    });
  });

  group('fixed-size cover boxes', () {
    test('card-less boxes are 2:3 with no inset to compensate for', () {
      for (final width in [kCompactCoverWidth, 96.0, 144.0]) {
        final boxHeight = mangaCoverBoxHeight(width, coverInset: 0);
        expect(
          width / boxHeight,
          closeTo(kMangaCoverAspectRatio, 0.0001),
          reason: '${width}px wide box',
        );
      }
    });

    test('list rows are the cover plus the tile padding', () {
      expect(
        kDescriptiveTileExtent,
        closeTo(
          mangaCoverBoxHeight(kDescriptiveCoverWidth) + kListTilePadding * 2,
          0.0001,
        ),
      );
      expect(
        kCompactTileExtent,
        closeTo(
          mangaCoverBoxHeight(kCompactCoverWidth, coverInset: 0) +
              kListTilePadding * 2,
          0.0001,
        ),
      );
    });

    test('artwork inside the box is 2:3 at every width we use', () {
      for (final width in [
        kDescriptiveCoverWidth,
        kShortSearchCoverWidth,
        96.0,
        200.0,
      ]) {
        final boxHeight = mangaCoverBoxHeight(width);
        final artRatio =
            (width - kMangaCoverCardInset) / (boxHeight - kMangaCoverCardInset);
        expect(
          artRatio,
          closeTo(kMangaCoverAspectRatio, 0.0001),
          reason: '${width}px wide box',
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
      final bare =
          const MangaCoverFixedCountGridDelegate(
                crossAxisCount: 3,
              ).getLayout(_constraints(411))
              as SliverGridRegularTileLayout;
      final withTitle =
          const MangaCoverFixedCountGridDelegate(
                crossAxisCount: 3,
                titleExtent: kGridTitleExtent,
              ).getLayout(_constraints(411))
              as SliverGridRegularTileLayout;

      expect(
        withTitle.childMainAxisExtent - bare.childMainAxisExtent,
        closeTo(kGridTitleExtent, 0.0001),
      );
      expect(withTitle.childCrossAxisExtent, bare.childCrossAxisExtent);
    });
  });
}
