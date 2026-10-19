// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../utils/extensions/custom_extensions.dart';
import '../../utils/platform/platform_runtime.dart';
import 'desktop_title_bar.dart';

/// Wraps the app with the custom title bar on desktop. A Column, not an
/// overlay Stack — the opaque bar must push content down, never occlude it
/// (macOS traffic lights float over the bar's left edge).
///
/// Once the desktop layout applies, the shell draws the merged top bar (or
/// the two-row fallback) itself, so no strip is drawn here; narrower windows
/// keep the standalone strip above the page's own bars.
class DesktopWindowScaffold extends StatelessWidget {
  const DesktopWindowScaffold({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isDesktopPlatform) return child;
    if (context.isDesktop) return child;

    return Column(
      children: [
        const DesktopTitleBar(),
        Expanded(child: child),
      ],
    );
  }
}
