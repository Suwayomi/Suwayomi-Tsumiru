// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../../constants/app_theme.dart';
import '../../../routes/router_config.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/platform/platform_runtime.dart';
import '../presentation/appearance/widgets/app_theme_selector/app_theme_providers.dart';
import '../presentation/appearance/widgets/show_recommendations/show_recommendations_tile.dart';
import '../presentation/general/timeout_settings/timeout_settings_section.dart';
import '../widgets/app_theme_mode_tile/app_theme_mode_tile.dart';
import 'settings_search_entry.dart';

export 'settings_highlight_target.dart';
export 'settings_search_entry.dart';
export 'settings_search_row.dart';

/// Hand-written index of searchable settings, slice 1: General, Appearance,
/// Library. Later slices append their pages' lists here in page order.
///
/// Each entry's [SettingsSearchEntry.visible] mirrors the exact condition
/// that renders its tile — same provider, same comparison:
///
/// - General: Quick Search only exists on keyboard runtimes (same
///   [isKeyboardRuntime] gate as the screen); Auto-refresh Retry Delay only
///   renders while auto-refresh is on. Everything else always renders.
/// - Appearance: Pure black only renders when the theme mode isn't light;
///   Custom color only renders with the Custom theme; Recommendations in
///   overflow unmounts while recommendations are off. The rest always render.
/// - Library: every tile renders unconditionally (permission gates only
///   disable the tap, the tile stays on screen), so every entry is always
///   visible.
///
/// The drift-guard test (`settings_registry_drift_test.dart`) pumps each page
/// with every condition satisfied and checks both directions, so add an entry
/// and wrap its tile together — one without the other fails the suite.
List<SettingsSearchEntry> get generalSettingsSearchEntries => [
  SettingsSearchEntry(
    id: 'appLanguage',
    title: (l) => l.appLanguage,
    breadcrumb: (l) => l.general,
    open: (c) => const GeneralSettingsRoute(highlight: 'appLanguage').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'clearCache',
    title: (l) => l.clearCache,
    breadcrumb: (l) => l.general,
    open: (c) => const GeneralSettingsRoute(highlight: 'clearCache').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'quickSearch',
    title: (l) => l.quickSearch,
    breadcrumb: (l) => l.general,
    open: (c) => const GeneralSettingsRoute(highlight: 'quickSearch').push(c),
    visible: (_, _) => isKeyboardRuntime,
  ),
  SettingsSearchEntry(
    id: 'lockToPortrait',
    title: (l) => l.lockToPortrait,
    subtitle: (l) => l.lockToPortraitSubtitle,
    breadcrumb: (l) => l.general,
    open: (c) =>
        const GeneralSettingsRoute(highlight: 'lockToPortrait').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'serverRequestTimeout',
    title: (l) => l.serverRequestTimeout,
    subtitle: (l) => l.serverRequestTimeoutDescription,
    breadcrumb: (l) => '${l.general} › ${l.timeoutSettings}',
    open: (c) =>
        const GeneralSettingsRoute(highlight: 'serverRequestTimeout').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'autoRefreshOnTimeout',
    title: (l) => l.autoRefreshOnTimeout,
    subtitle: (l) => l.autoRefreshOnTimeoutDescription,
    breadcrumb: (l) => '${l.general} › ${l.timeoutSettings}',
    open: (c) =>
        const GeneralSettingsRoute(highlight: 'autoRefreshOnTimeout').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'autoRefreshRetryDelay',
    title: (l) => l.autoRefreshRetryDelay,
    subtitle: (l) => l.autoRefreshRetryDelayDescription,
    breadcrumb: (l) => '${l.general} › ${l.timeoutSettings}',
    open: (c) =>
        const GeneralSettingsRoute(highlight: 'autoRefreshRetryDelay').push(c),
    visible: (ref, _) => ref.watch(autoRefreshOnTimeoutProvider).ifNull(),
  ),
];

List<SettingsSearchEntry> get appearanceSettingsSearchEntries => [
  SettingsSearchEntry(
    id: 'appThemeMode',
    title: (l) => l.appTheme,
    breadcrumb: (l) => l.appearance,
    open: (c) =>
        const AppearanceSettingsRoute(highlight: 'appThemeMode').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'pureBlack',
    title: (l) => l.pureBlackAmoled,
    breadcrumb: (l) => l.appearance,
    open: (c) => const AppearanceSettingsRoute(highlight: 'pureBlack').push(c),
    visible: (ref, _) => ref.watch(appThemeModeProvider) != ThemeMode.light,
  ),
  SettingsSearchEntry(
    id: 'theme',
    title: (l) => l.appThemeTitle,
    breadcrumb: (l) => '${l.appearance} › ${l.appThemeTitle}',
    open: (c) => const AppearanceSettingsRoute(highlight: 'theme').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'customColor',
    title: (l) => l.customColor,
    breadcrumb: (l) => '${l.appearance} › ${l.appThemeTitle}',
    open: (c) =>
        const AppearanceSettingsRoute(highlight: 'customColor').push(c),
    visible: (ref, _) => ref.watch(appThemeKeyProvider) == AppTheme.custom,
  ),
  SettingsSearchEntry(
    id: 'mangaGridSize',
    title: (l) => l.mangaGridSize,
    breadcrumb: (l) => l.appearance,
    open: (c) =>
        const AppearanceSettingsRoute(highlight: 'mangaGridSize').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'showRecommendations',
    title: (l) => l.showRecommendations,
    subtitle: (l) => l.showRecommendationsSubtitle,
    breadcrumb: (l) => l.appearance,
    open: (c) =>
        const AppearanceSettingsRoute(highlight: 'showRecommendations').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'recommendsInOverflow',
    title: (l) => l.recommendsInOverflow,
    subtitle: (l) => l.recommendsInOverflowSubtitle,
    breadcrumb: (l) => l.appearance,
    open: (c) => const AppearanceSettingsRoute(
      highlight: 'recommendsInOverflow',
    ).push(c),
    visible: (ref, _) => ref.watch(showRecommendationsProvider).ifNull(true),
  ),
];

List<SettingsSearchEntry> get librarySettingsSearchEntries => [
  SettingsSearchEntry(
    id: 'categories',
    title: (l) => l.categories,
    breadcrumb: (l) => '${l.library} › ${l.general}',
    open: (c) => const LibrarySettingsRoute(highlight: 'categories').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'defaultCategory',
    title: (l) => l.defaultCategoryOnAdd,
    breadcrumb: (l) => '${l.library} › ${l.general}',
    open: (c) =>
        const LibrarySettingsRoute(highlight: 'defaultCategory').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'refreshChaptersFromSource',
    title: (l) => l.refreshChaptersFromSource,
    subtitle: (l) => l.refreshChaptersFromSourceSubtitle,
    breadcrumb: (l) => '${l.library} › ${l.general}',
    open: (c) => const LibrarySettingsRoute(
      highlight: 'refreshChaptersFromSource',
    ).push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'persistentSearchBar',
    title: (l) => l.libraryPersistentSearchBar,
    subtitle: (l) => l.libraryPersistentSearchBarSubtitle,
    breadcrumb: (l) => '${l.library} › ${l.general}',
    open: (c) =>
        const LibrarySettingsRoute(highlight: 'persistentSearchBar').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'automaticUpdate',
    title: (l) => l.automaticUpdate,
    breadcrumb: (l) => '${l.library} › ${l.globalUpdate}',
    open: (c) =>
        const LibrarySettingsRoute(highlight: 'automaticUpdate').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'automaticallyRefreshMetadata',
    title: (l) => l.automaticallyRefreshMetadata,
    subtitle: (l) => l.automaticallyRefreshMetadataSubtitle,
    breadcrumb: (l) => '${l.library} › ${l.globalUpdate}',
    open: (c) => const LibrarySettingsRoute(
      highlight: 'automaticallyRefreshMetadata',
    ).push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'skipUpdatingEntries',
    title: (l) => l.skipUpdatingEntries,
    breadcrumb: (l) => '${l.library} › ${l.globalUpdate}',
    open: (c) =>
        const LibrarySettingsRoute(highlight: 'skipUpdatingEntries').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'updateCategories',
    title: (l) => l.updateCategories,
    breadcrumb: (l) => '${l.library} › ${l.globalUpdate}',
    open: (c) =>
        const LibrarySettingsRoute(highlight: 'updateCategories').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'duplicatedEntries',
    title: (l) => l.duplicatedEntries,
    subtitle: (l) => l.duplicatedEntriesSubtitle,
    breadcrumb: (l) => '${l.library} › ${l.globalUpdate}',
    open: (c) =>
        const LibrarySettingsRoute(highlight: 'duplicatedEntries').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'chapterSwipeToLeft',
    title: (l) => l.chapterSwipeToLeft,
    breadcrumb: (l) => '${l.library} › ${l.globalUpdate}',
    open: (c) =>
        const LibrarySettingsRoute(highlight: 'chapterSwipeToLeft').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'chapterSwipeToRight',
    title: (l) => l.chapterSwipeToRight,
    breadcrumb: (l) => '${l.library} › ${l.globalUpdate}',
    open: (c) =>
        const LibrarySettingsRoute(highlight: 'chapterSwipeToRight').push(c),
    visible: (_, _) => true,
  ),
];

/// Every registered entry in result order: General, Appearance, Library.
List<SettingsSearchEntry> get allSettingsSearchEntries => [
  ...generalSettingsSearchEntries,
  ...appearanceSettingsSearchEntries,
  ...librarySettingsSearchEntries,
];
