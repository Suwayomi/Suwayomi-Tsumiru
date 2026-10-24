// Copyright (c) 2023 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/legacy.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import '../../../settings/presentation/general/quick_search_toggle/quick_search_toggle_tile.dart';
import '../unified_search/unified_search_screen.dart';

// GlobalShortcutHost owns focus and toggles this state from outside the overlay.
final quickOpenVisibleProvider = StateProvider<bool>((Ref ref) => false);

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
        ?child,
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
                child: UnifiedSearchScreen(afterClick: hide),
              ),
            ),
          ),
      ],
    );
  }
}
