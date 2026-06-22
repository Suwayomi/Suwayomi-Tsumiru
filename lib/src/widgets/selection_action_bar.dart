// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../constants/app_sizes.dart';
import '../utils/extensions/custom_extensions.dart';

/// Shared floating bottom action bar for multi-select modes (library manga and
/// chapter selection use the same look). A translucent rounded [Card] holding an
/// optional [leading] cluster (e.g. close + count + select-all) on the left and
/// a row of action buttons on the right; when [leading] is empty the actions are
/// spaced evenly (the chapter-selection layout, whose count/close/select-all
/// live in the screen's app bar instead).
///
/// Reads the bottom inset straight from the [FlutterView]: this bar is rendered
/// inside the shell navigation / a Scaffold bottomSheet, which zero out the
/// bottom MediaQuery insets (both padding and viewPadding) for descendants, so a
/// MediaQuery/SafeArea would not clear the Android navigation bar.
class SelectionActionBar extends StatelessWidget {
  const SelectionActionBar({
    super.key,
    this.leading = const [],
    required this.actions,
    this.clearsSystemNav = false,
  });

  final List<Widget> leading;
  final List<Widget> actions;

  /// Add the system navigation-bar inset below the card. True when the bar sits
  /// directly over the system nav (a pushed screen's bottomSheet, e.g. chapter
  /// selection). False when an app bottom NavigationBar already sits between
  /// this bar and the system nav (the library tab) — otherwise the inset is
  /// double-counted and the bar floats too high above the nav bar.
  final bool clearsSystemNav;

  @override
  Widget build(BuildContext context) {
    final view = View.of(context);
    final bottomInset =
        clearsSystemNav ? view.viewPadding.bottom / view.devicePixelRatio : 0.0;
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
                    const Spacer(),
                    ...actions,
                  ],
                ),
        ),
      ),
    );
  }
}
