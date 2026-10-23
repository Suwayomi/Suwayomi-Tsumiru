// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/app_theme.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../search/settings_search_registry.dart';
import '../../widgets/app_theme_mode_tile/app_theme_mode_tile.dart';
import '../../widgets/settings_group_card/settings_group_card.dart';
import 'widgets/app_theme_selector/app_theme_providers.dart';
import 'widgets/app_theme_selector/app_theme_selector.dart';
import 'widgets/grid_cover_width_slider/grid_cover_width_slider.dart';
import 'widgets/is_true_black/is_true_black_tile.dart';
import 'widgets/show_recommendations/show_recommendations_tile.dart';

class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(context, ref) {
    final themeMode = ref.watch(appThemeModeProvider);
    final theme = ref.watch(appThemeKeyProvider);
    final showRecommendations = ref.watch(showRecommendationsProvider);
    // Native desktop draws the toolbar in the shell bar instead of an app
    // bar.
    final topBar = showsMergedTopBar(context);
    final title = Text(context.l10n.appearance);
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
                SettingsGroupHeading(
                  label: context.l10n.appThemeTitle,
                  first: true,
                ),
                SettingsGroupCard(
                  children: [
                    const SettingsHighlightTarget(
                      id: 'appThemeMode',
                      child: AppThemeModeTile(),
                    ),
                    // The card heading already names the theme section, so the
                    // picker renders without its own title row.
                    const SettingsHighlightTarget(
                      id: 'theme',
                      child: ThemeSelector(),
                    ),
                    if (theme == AppTheme.custom)
                      const SettingsHighlightTarget(
                        id: 'customColor',
                        child: CustomColorTile(),
                      ),
                    if (themeMode != ThemeMode.light)
                      const SettingsHighlightTarget(
                        id: 'pureBlack',
                        child: IsTrueBlackTile(),
                      ),
                  ],
                ),
                SettingsGroupHeading(label: context.l10n.display),
                SettingsGroupCard(
                  children: [
                    const SettingsHighlightTarget(
                      id: 'mangaGridSize',
                      child: GridCoverWidthSlider(),
                    ),
                    const SettingsHighlightTarget(
                      id: 'showRecommendations',
                      child: ShowRecommendationsTile(),
                    ),
                    if (showRecommendations.ifNull(true))
                      const SettingsHighlightTarget(
                        id: 'recommendsInOverflow',
                        child: RecommendsInOverflowTile(),
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
