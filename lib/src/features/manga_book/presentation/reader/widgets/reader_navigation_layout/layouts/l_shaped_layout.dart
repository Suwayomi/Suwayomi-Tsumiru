// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

class LShapedLayout extends StatelessWidget {
  const LShapedLayout({
    super.key,
    this.onLeftTap,
    this.onRightTap,
    this.leftColor,
    this.rightColor,
    this.onTopTap,
    this.onBottomTap,
    this.topColor,
    this.bottomColor,
    this.smaller = false,
  });

  final VoidCallback? onLeftTap;
  final VoidCallback? onRightTap;
  final Color? leftColor;
  final Color? rightColor;

  // Vertical-axis zones (top/bottom rows); fall back to the horizontal
  // assignments so callers without axis-wise invert keep the old behavior.
  final VoidCallback? onTopTap;
  final VoidCallback? onBottomTap;
  final Color? topColor;
  final Color? bottomColor;

  /// Komikku "smaller tap zones": prev/next bands 0.25 (flex 1:2:1) vs 0.33.
  final bool smaller;
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onTopTap ?? onLeftTap,
            child: Container(color: topColor ?? leftColor),
          ),
        ),
        Expanded(
          flex: smaller ? 2 : 1,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: onLeftTap,
                  child: Container(color: leftColor),
                ),
              ),
              Expanded(flex: smaller ? 2 : 1, child: const SizedBox.expand()),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: onRightTap,
                  child: Container(color: rightColor),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onBottomTap ?? onRightTap,
            child: Container(color: bottomColor ?? rightColor),
          ),
        ),
      ],
    );
  }
}
