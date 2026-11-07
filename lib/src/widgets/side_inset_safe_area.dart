// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:material_ui/material_ui.dart';

import '../utils/extensions/custom_extensions.dart';

/// Keeps compact layouts out of side insets.
///
/// iPhone Duo's outer display is a compact portrait window with the status
/// bar and camera in a full-height column at its side, reported as
/// `MediaQuery.padding.right`. Widgets that set their own padding (grids,
/// most list and detail pages) drop MediaQuery's side insets, so their content
/// ran under that column. Other phones report no side insets in compact
/// windows, and medium and wider layouts already apply [SafeArea] in the
/// navigation shell, so this only changes anything where a compact window has
/// side insets.
///
/// The tree has the same shape whether or not the insets apply, so rotating
/// between compact and medium does not remount [child].
class SideInsetSafeArea extends StatelessWidget {
  const SideInsetSafeArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final apply = context.windowSizeClass == WindowSizeClass.compact;
    final left = apply ? padding.left : 0.0;
    final right = apply ? padding.right : 0.0;
    return ColoredBox(
      // Fills the inset with the page colour, not the bare window.
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Padding(
        padding: EdgeInsets.only(left: left, right: right),
        child: MediaQuery.removePadding(
          context: context,
          removeLeft: apply,
          removeRight: apply,
          child: child,
        ),
      ),
    );
  }
}
