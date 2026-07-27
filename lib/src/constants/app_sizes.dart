// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'app_constants.dart';
import 'db_keys.dart';

const kTabSize = Size.fromHeight(kAppBarBottomHeight);
const kAppBarBottomHeight = 46.0;
const kDrawerWidth = 384.0;

Size kCalculateAppBarBottomSize(List<bool> checks) {
  final multiplier =
      checks.map((e) => e ? 1 : 0).toList().fold(0, (v1, v2) => v1 + v2);
  return Size.fromHeight(kAppBarBottomHeight * multiplier);
}

Offset kMagnifierPosition(Offset position, Size size, double multiplier) =>
    Offset(
      max(
        min(
          position.dx - (kMagnifierSize.width * multiplier * .5),
          size.width - (kMagnifierSize.width * multiplier * .5),
        ),
        -(kMagnifierSize.width * multiplier * .5),
      ),
      max(
        min(
          position.dy - (kMagnifierSize.height * multiplier),
          size.height - (kMagnifierSize.height * multiplier * 1.25),
        ),
        -(kMagnifierSize.height * multiplier * .5),
      ),
    );

Offset kMagnifierOffset(Offset position, Size size, double multiplier) {
  return Offset(
    0,
    max(0, min(position.dy, (kMagnifierSize.height * multiplier))) * .5,
  );
}

/// Constant sizes to be used in the app (paddings, gaps, rounded corners etc.)
enum KEdgeInsets {
  a2(EdgeInsets.all(2)),
  a4(EdgeInsets.all(4)),
  a8(EdgeInsets.all(8)),
  a16(EdgeInsets.all(16)),
  h8v4(EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
  h8v16(EdgeInsets.symmetric(horizontal: 8, vertical: 16)),
  h16v8(EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0)),
  h4v8(EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0)),
  h16v4(EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0)),
  h16(EdgeInsets.symmetric(horizontal: 16.0)),
  h8(EdgeInsets.symmetric(horizontal: 8.0)),
  v8(EdgeInsets.symmetric(vertical: 8)),
  v16(EdgeInsets.symmetric(vertical: 16)),
  v4(EdgeInsets.symmetric(vertical: 4)),
  h4(EdgeInsets.symmetric(horizontal: 4)),
  ol4(EdgeInsets.only(left: 4)),
  ;

  const KEdgeInsets(this.size);

  final EdgeInsets size;
}

enum KBorderRadius {
  r8(BorderRadius.all(Radius.circular(8))),
  r12(BorderRadius.all(Radius.circular(12))),
  r16(BorderRadius.all(Radius.circular(16))),
  rT16(BorderRadius.vertical(top: Radius.circular(16))),
  r32(BorderRadius.all(Radius.circular(32))),
  ;

  const KBorderRadius(this.radius);
  final BorderRadius radius;
}

enum KRadius {
  r8(Radius.circular(8)),
  r12(Radius.circular(12)),
  r16(Radius.circular(16)),
  rT16(Radius.circular(16)),
  r32(Radius.circular(32)),
  ;

  const KRadius(this.radius);
  final Radius radius;
}

/// Manga covers are 2:3, matching Komikku's `MangaCover.Book`.
const kMangaCoverAspectRatio = 2 / 3;

/// Height reserved for the two-line title under a comfortable-grid cover.
const kGridTitleExtent = 44.0;

/// Total inset the tile's Card takes out of each axis — Flutter's default card
/// margin of 4 on all four sides. The cell is grown by this so the artwork
/// inside the card, not the cell, is what ends up at 2:3.
const kMangaCoverCardInset = 8.0;

/// Cover width in the descriptive list tile — manga details header and the
/// library's list view.
const kDescriptiveCoverWidth = 120.0;

/// Cover width in the horizontal result strips (global search, migration).
const kShortSearchCoverWidth = 144.0;

/// Gap plus the two-line bodySmall title under a recommendation cover.
const kRecommendsTitleExtent = 36.0;

/// Cover width in the compact list tile, which draws the image directly.
const kCompactCoverWidth = 60.0;

/// Padding around a list tile's cover.
const kListTilePadding = 8.0;

/// Height a fixed-width cover box needs for its artwork to land on 2:3. Pass
/// `coverInset: 0` where the cover is drawn directly rather than inside the
/// tile's Card. Use this instead of hard-coding a height next to a width.
double mangaCoverBoxHeight(
  double width, {
  double coverInset = kMangaCoverCardInset,
}) =>
    max(0.0, width - coverInset) / kMangaCoverAspectRatio + coverInset;

/// Row heights for the two list views. Derived, because the covers grew when
/// they were corrected to 2:3 and a stale literal here clips the tile.
final kDescriptiveTileExtent =
    mangaCoverBoxHeight(kDescriptiveCoverWidth) + kListTilePadding * 2;
final kCompactTileExtent =
    mangaCoverBoxHeight(kCompactCoverWidth, coverInset: 0) +
        kListTilePadding * 2;

/// Row height comes from the resolved column width, so the cover keeps its 2:3
/// shape at every column count. Deriving it the other way round — a fixed cell
/// ratio, cover takes what's left — cropped the art, and in the comfortable
/// grid the error grew as columns got narrower.
SliverGridRegularTileLayout _coverTileLayout(
  SliverConstraints constraints, {
  required int crossAxisCount,
  required double crossAxisSpacing,
  required double mainAxisSpacing,
  required double titleExtent,
  required double coverInset,
}) {
  final usableCrossAxisExtent = max(
    0.0,
    constraints.crossAxisExtent - crossAxisSpacing * (crossAxisCount - 1),
  );
  final childCrossAxisExtent = usableCrossAxisExtent / crossAxisCount;
  final coverWidth = max(0.0, childCrossAxisExtent - coverInset);
  final childMainAxisExtent =
      coverWidth / kMangaCoverAspectRatio + coverInset + titleExtent;
  return SliverGridRegularTileLayout(
    crossAxisCount: crossAxisCount,
    mainAxisStride: childMainAxisExtent + mainAxisSpacing,
    crossAxisStride: childCrossAxisExtent + crossAxisSpacing,
    childMainAxisExtent: childMainAxisExtent,
    childCrossAxisExtent: childCrossAxisExtent,
    reverseCrossAxis: axisDirectionIsReversed(constraints.crossAxisDirection),
  );
}

/// Width-driven columns (the "auto" library layout).
class MangaCoverGridDelegate extends SliverGridDelegate {
  const MangaCoverGridDelegate({
    required this.maxCrossAxisExtent,
    this.mainAxisSpacing = 0.0,
    this.crossAxisSpacing = 0.0,
    this.titleExtent = 0.0,
    this.coverInset = kMangaCoverCardInset,
  }) : assert(maxCrossAxisExtent > 0);

  final double maxCrossAxisExtent;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final double titleExtent;

  /// Zero for grids that draw the cover directly instead of wrapping it in the
  /// tile's Card, which is what eats the default margin.
  final double coverInset;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) => _coverTileLayout(
        constraints,
        crossAxisCount: max(
          1,
          (constraints.crossAxisExtent /
                  (maxCrossAxisExtent + crossAxisSpacing))
              .ceil(),
        ),
        crossAxisSpacing: crossAxisSpacing,
        mainAxisSpacing: mainAxisSpacing,
        titleExtent: titleExtent,
        coverInset: coverInset,
      );

  @override
  bool shouldRelayout(MangaCoverGridDelegate oldDelegate) =>
      oldDelegate.maxCrossAxisExtent != maxCrossAxisExtent ||
      oldDelegate.mainAxisSpacing != mainAxisSpacing ||
      oldDelegate.crossAxisSpacing != crossAxisSpacing ||
      oldDelegate.titleExtent != titleExtent ||
      oldDelegate.coverInset != coverInset;
}

/// Fixed column count (the user set one in library settings).
class MangaCoverFixedCountGridDelegate extends SliverGridDelegate {
  const MangaCoverFixedCountGridDelegate({
    required this.crossAxisCount,
    this.mainAxisSpacing = 0.0,
    this.crossAxisSpacing = 0.0,
    this.titleExtent = 0.0,
  }) : assert(crossAxisCount > 0);

  final int crossAxisCount;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final double titleExtent;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) => _coverTileLayout(
        constraints,
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: crossAxisSpacing,
        mainAxisSpacing: mainAxisSpacing,
        titleExtent: titleExtent,
        coverInset: kMangaCoverCardInset,
      );

  @override
  bool shouldRelayout(MangaCoverFixedCountGridDelegate oldDelegate) =>
      oldDelegate.crossAxisCount != crossAxisCount ||
      oldDelegate.mainAxisSpacing != mainAxisSpacing ||
      oldDelegate.crossAxisSpacing != crossAxisSpacing ||
      oldDelegate.titleExtent != titleExtent;
}

/// [titleBelow] (comfortable grid) adds the title block under the cover.
SliverGridDelegate mangaCoverGridDelegate(
  double? size, {
  bool titleBelow = false,
}) =>
    MangaCoverGridDelegate(
      maxCrossAxisExtent: size ?? DBKeys.gridMangaCoverWidth.initial,
      crossAxisSpacing: 2.0,
      mainAxisSpacing: 2.0,
      titleExtent: titleBelow ? kGridTitleExtent : 0.0,
    );
