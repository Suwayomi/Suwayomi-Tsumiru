// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../utils/platform/platform_runtime.dart';
import 'desktop_title_bar.dart';
import 'desktop_top_bar.dart';

/// Wraps the app with the custom title bar on native desktop. A Column, not
/// an overlay Stack — the opaque bar must push content down, never occlude it
/// (macOS traffic lights float over the bar's left edge).
///
/// The standalone strip is drawn unless the displayed route already provides
/// the merged top bar ([showsMergedTopBar], the same gate the shells use):
/// the navigation shells register while they show it, so Library and the
/// detail pages get no second strip, while routes outside the shells
/// (reader, onboarding) keep the strip with its window controls and drag
/// area. Narrower windows keep the strip too, since the shells draw no
/// merged bar there. Off native desktop (web, tablets) there is never a
/// strip: the shells' merged bar owns the top, and routes outside the shells
/// draw nothing.
class DesktopWindowScaffold extends ConsumerWidget {
  const DesktopWindowScaffold({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mergedBarVisible = ref.watch(mergedTopBarRegistryProvider) > 0;
    if (showsMergedTopBar(context) && mergedBarVisible) return child;
    if (!isDesktopPlatform) return child;

    return Column(
      children: [
        const DesktopTitleBar(),
        Expanded(child: child),
      ],
    );
  }
}
