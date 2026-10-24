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

/// Native title strip appears only without a displayed merged bar; reserve its height above content.
class DesktopWindowScaffold extends ConsumerWidget {
  const DesktopWindowScaffold({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isDesktopPlatform) return child;
    final mergedBarVisible = ref.watch(mergedTopBarRegistryProvider) > 0;
    // Keep Router mounted: re-parsing route info loses non-JSON extras on resize.
    final showTitleBar = !(showsMergedTopBar(context) && mergedBarVisible);
    return Column(
      children: [
        showTitleBar ? const DesktopTitleBar() : const SizedBox.shrink(),
        Expanded(child: child),
      ],
    );
  }
}
