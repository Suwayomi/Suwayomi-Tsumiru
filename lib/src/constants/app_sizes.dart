// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math';

import 'package:flutter/rendering.dart';

import 'db_keys.dart';

const kTabSize = Size.fromHeight(kAppBarBottomHeight);
const kAppBarBottomHeight = 46.0;
const kDrawerWidth = 384.0;

Size kCalculateAppBarBottomSize(List<bool> checks) {
  final multiplier =
      checks.map((e) => e ? 1 : 0).toList().fold(0, (v1, v2) => v1 + v2);
  return Size.fromHeight(kAppBarBottomHeight * multiplier);
}

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

const kMangaCoverAspectRatio = 2 / 3;

const kGridTitleExtent = 44.0;

/// Flutter's default Card margin removes 4 px from each edge.
const kMangaCoverCardInset = 8.0;

const kDescriptiveCoverWidth = 120.0;

const kShortSearchCoverWidth = 144.0;

const kRecommendsTitleExtent = 36.0;

const kCompactCoverWidth = 60.0;

const kListTilePadding = 8.0;

/// Pass coverInset: 0 when drawing artwork directly rather than inside a Card.
double mangaCoverBoxHeight(
  double width, {
  double coverInset = kMangaCoverCardInset,
}) =>
    max(0.0, width - coverInset) / kMangaCoverAspectRatio + coverInset;

final kDescriptiveTileExtent =
    mangaCoverBoxHeight(kDescriptiveCoverWidth) + kListTilePadding * 2;
final kCompactTileExtent =
    mangaCoverBoxHeight(kCompactCoverWidth, coverInset: 0) +
        kListTilePadding * 2;

/// Derive height from resolved cover width to preserve 2:3 at every column count.
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

  /// Zero when drawing the cover directly, without Card margins.
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
