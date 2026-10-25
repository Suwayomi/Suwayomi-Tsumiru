// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../constants/app_sizes.dart';
import '../utils/extensions/custom_extensions.dart';

/// Read insets from FlutterView: shell/bottomSheet MediaQuery insets are zeroed.
class SelectionActionBar extends StatelessWidget {
  const SelectionActionBar({
    super.key,
    this.leading = const [],
    required this.actions,
    this.clearsSystemNav = false,
  });

  final List<Widget> leading;
  final List<Widget> actions;

  /// Add the system inset only when no app navigation bar already reserves it.
  final bool clearsSystemNav;

  @override
  Widget build(BuildContext context) {
    final view = View.of(context);
    final bottomInset = clearsSystemNav
        ? view.viewPadding.bottom / view.devicePixelRatio
        : 0.0;
    return Padding(
      padding: KEdgeInsets.a8.size.add(EdgeInsets.only(bottom: bottomInset)),
      child: Card(
        margin: EdgeInsets.zero,
        color: context.theme.cardColor.withValues(alpha: 0.97),
        shape: RoundedRectangleBorder(borderRadius: KBorderRadius.r12.radius),
        child: Padding(
          padding: KEdgeInsets.h8v4.size,
          child: leading.isEmpty
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: actions,
                )
              : Row(
                  children: [
                    ...leading,
                    Flexible(
                      child: Align(
                        alignment: Alignment.centerRight,
                        heightFactor: 1.0,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(children: actions),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
