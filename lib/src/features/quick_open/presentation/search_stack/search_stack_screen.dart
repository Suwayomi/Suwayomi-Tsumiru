// Copyright (c) 2023 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import '../../../settings/presentation/general/quick_search_toggle/quick_search_toggle_tile.dart';
import '../quick_search/quick_search_screen.dart';

/// Whether the quick-open overlay is showing. The keyboard shortcuts that
/// open it live in the app-wide GlobalShortcutHost (which holds focus, unlike
/// this deep-in-the-tree widget), so they toggle this provider rather than a
/// local state.
final quickOpenVisibleProvider = StateProvider<bool>((ref) => false);

class SearchStackScreen extends ConsumerWidget {
  const SearchStackScreen({super.key, this.child});
  final Widget? child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isQuickSearchEnabled = ref.watch(quickSearchToggleProvider).ifNull();
    if (!isQuickSearchEnabled) return child!;
    final visible = ref.watch(quickOpenVisibleProvider);
    void hide() => ref.read(quickOpenVisibleProvider.notifier).state = false;
    return Stack(
      children: [
        if (child != null) child!,
        if (visible)
          GestureDetector(
            onTap: hide,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Container(
                constraints: const BoxConstraints.expand(),
                decoration: BoxDecoration(
                  color: context.theme.canvasColor.withValues(alpha: .1),
                ),
                child: QuickSearchScreen(afterClick: hide),
              ),
            ),
          ),
      ],
    );
  }
}
