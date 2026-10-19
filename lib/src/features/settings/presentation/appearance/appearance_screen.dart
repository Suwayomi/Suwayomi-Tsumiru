// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/app_theme.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/section_title.dart';
import '../../search/settings_search_registry.dart';
import '../../widgets/app_theme_mode_tile/app_theme_mode_tile.dart';
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
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.appearance)),
      body: SettingsHighlightScope(
        child: ListView(
          children: [
          const SettingsHighlightTarget(
            id: 'appThemeMode',
            child: AppThemeModeTile(),
          ),
          if (themeMode != ThemeMode.light)
            const SettingsHighlightTarget(
              id: 'pureBlack',
              child: IsTrueBlackTile(),
            ),
          SettingsHighlightTarget(
            id: 'theme',
            child: ThemeSelector(
              title: SectionTitle(title: context.l10n.appThemeTitle),
            ),
          ),
          SettingsHighlightTarget(
            id: 'customColor',
            child: Consumer(
              builder: (context, ref, _) {
                final theme = ref.watch(appThemeKeyProvider);
                return theme == AppTheme.custom
                    ? const CustomColorTile()
                    : const SizedBox.shrink();
              },
            ),
          ),
          const SettingsHighlightTarget(
            id: 'mangaGridSize',
            child: GridCoverWidthSlider(),
          ),
          const SettingsHighlightTarget(
            id: 'showRecommendations',
            child: ShowRecommendationsTile(),
          ),
            const SettingsHighlightTarget(
              id: 'recommendsInOverflow',
              child: RecommendsInOverflowTile(),
            ),
          ],
        ),
      ),
    );
  }
}
