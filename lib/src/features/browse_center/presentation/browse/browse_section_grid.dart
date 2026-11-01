// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/desktop/desktop_page_frame.dart';

SliverGridDelegate browseCardGridDelegate(double extent) =>
    SliverGridDelegateWithFixedCrossAxisCount(
  crossAxisCount: 3,
  mainAxisSpacing: 12,
  crossAxisSpacing: 12,
  mainAxisExtent: extent,
);

class BrowseSectionHeading extends StatelessWidget {
  const BrowseSectionHeading({
    super.key,
    required this.title,
    this.count,
    this.trailing,
    this.topPadding = 16,
  });

  final String title;
  final int? count;
  final Widget? trailing;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    final titleText = Text(title, style: context.theme.textTheme.titleSmall);
    final padding = EdgeInsets.only(
      left: 4,
      right: 4,
      top: topPadding,
      bottom: 8,
    ).onDesktopPageLine(context);
    if (count == null && trailing == null) {
      return Padding(padding: padding, child: titleText);
    }
    return Padding(
      padding: padding,
      child: Row(
        children: [
          titleText,
          if (count != null) ...[
            const SizedBox(width: 8),
            Text(
              '$count',
              style: context.theme.textTheme.bodySmall?.copyWith(
                color: context.theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const Spacer(),
          trailing ?? const SizedBox.shrink(),
        ],
      ),
    );
  }
}

class BrowseCardGrid extends StatelessWidget {
  const BrowseCardGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.mainAxisExtent = 84,
  });

  const BrowseCardGrid.source({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
  }) : mainAxisExtent = 104;

  final int itemCount;
  final NullableIndexedWidgetBuilder itemBuilder;
  final double mainAxisExtent;

  @override
  Widget build(BuildContext context) => SliverGrid(
    gridDelegate: browseCardGridDelegate(
      mainAxisExtent * browseCardTextScale(context),
    ),
    delegate: SliverChildBuilderDelegate(itemBuilder, childCount: itemCount),
  );
}

double browseCardTextScale(BuildContext context) =>
    math.max(1, MediaQuery.textScalerOf(context).scale(12) / 12);
