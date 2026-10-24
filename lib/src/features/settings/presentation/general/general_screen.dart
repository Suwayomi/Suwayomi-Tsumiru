// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/platform/platform_runtime.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../search/settings_search_registry.dart';
import '../../widgets/settings_group_card/settings_group_card.dart';
import '../library/widgets/persistent_search_bar/persistent_search_bar.dart';
import 'quick_search_toggle/quick_search_toggle_tile.dart';
import 'widgets/force_portrait_tile.dart';

class GeneralScreen extends ConsumerWidget {
  const GeneralScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final highlight = GoRouter.maybeOf(
      context,
    )?.state.uri.queryParameters['highlight'];
    if (highlight == 'appLanguage') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          const AppearanceSettingsRoute(highlight: 'appLanguage').go(context);
        }
      });
    }

    final topBar = showsMergedTopBar(context);
    final title = Text(context.l10n.general);
    final scaffold = Scaffold(
      appBar: topBar
          ? null
          : AppBar(leading: detailNavigationBackButton(context), title: title),
      body: SettingsHighlightScope(
        child: Center(
          child: ConstrainedBox(
            constraints: settingsPageConstraints(context),
            child: ListView(
              padding: settingsPagePadding(context),
              children: [
                const SizedBox(height: 16),
                SettingsGroupCard(
                  children: [
                    SettingsHighlightTarget(
                      id: 'lockToPortrait',
                      child: ForcePortraitTile(),
                    ),
                    const SettingsHighlightTarget(
                      id: 'persistentSearchBar',
                      child: PersistentSearchBarTile(),
                    ),
                    // Quick search requires a keyboard shortcut to open.
                    if (isKeyboardRuntime)
                      const SettingsHighlightTarget(
                        id: 'quickSearch',
                        child: QuickSearchToggleTile(),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return titleTopBarSlot(
      topBar: topBar,
      leading: detailNavigationBackButton(context),
      title: title,
      child: scaffold,
    );
  }
}
