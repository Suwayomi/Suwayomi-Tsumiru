// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

class RightAndLeftLayout extends StatelessWidget {
  const RightAndLeftLayout({
    super.key,
    this.onLeftTap,
    this.onRightTap,
    this.leftColor,
    this.rightColor,
    this.smaller = false,
  });
  final VoidCallback? onLeftTap;
  final VoidCallback? onRightTap;
  final Color? leftColor;
  final Color? rightColor;

  /// Komikku "smaller tap zones": edge width 0.25 (flex 1:2:1) vs 0.33 (1:1:1).
  final bool smaller;
  @override
  Widget build(BuildContext context) {
    return Row(
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
    );
  }
}
