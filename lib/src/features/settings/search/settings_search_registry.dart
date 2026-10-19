// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../constants/app_theme.dart';
import '../../../routes/router_config.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/platform/platform_runtime.dart';
import '../presentation/appearance/widgets/app_theme_selector/app_theme_providers.dart';
import '../presentation/appearance/widgets/show_recommendations/show_recommendations_tile.dart';
import '../presentation/general/timeout_settings/timeout_settings_section.dart';
import '../presentation/reader/widgets/reader_force_horizontal_seekbar_tile/reader_force_horizontal_seekbar_tile.dart';
import '../presentation/reader/widgets/reader_general_prefs/reader_general_prefs.dart';
import '../presentation/reader/widgets/reader_paged_prefs/reader_paged_prefs.dart';
import '../presentation/reader/widgets/reader_volume_tap_tile/reader_volume_tap_tile.dart';
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

/// Reader page (52 rows): ungrouped basics carry the plain "Reader"
/// breadcrumb, the rest "Reader › \<Section\>" with the real section header
/// strings. Rows that render greyed-out stay searchable (Long strip Maximum
/// width under Original size; the Paged zoom gestures while zoom-in is off),
/// so their entries are always visible. Conditional rows mirror the screen's
/// gate exactly: vertical-seekbar rows need force-horizontal off; cutout
/// needs fullscreen on; the flash rows need flash on; mouse speed needs a
/// keyboard runtime; invert-split/invert-rotate need split/rotate on;
/// keep-screen-on/ignore-safe-area need Android or iOS; the Navigation
/// section needs Android. Same providers, same helpers as the screen.
List<SettingsSearchEntry> get readerSettingsSearchEntries => [
  SettingsSearchEntry(
    id: 'readerMode',
    title: (l) => l.readerMode,
    breadcrumb: (l) => l.reader,
    open: (c) => const ReaderSettingsRoute(highlight: 'readerMode').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'showTapZonesOverlay',
    title: (l) => l.showTapZonesOverlay,
    subtitle: (l) => l.showTapZonesOverlaySubtitle,
    breadcrumb: (l) => l.reader,
    open: (c) =>
        const ReaderSettingsRoute(highlight: 'showTapZonesOverlay').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'smallerTapZones',
    title: (l) => l.smallerTapZones,
    breadcrumb: (l) => l.reader,
    open: (c) =>
        const ReaderSettingsRoute(highlight: 'smallerTapZones').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'forceHorizontalSeekbar',
    title: (l) => l.forceHorizontalSeekbar,
    breadcrumb: (l) => l.reader,
    open: (c) =>
        const ReaderSettingsRoute(highlight: 'forceHorizontalSeekbar').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'showVerticalSeekbar',
    title: (l) => l.showVerticalSeekbarInLandscape,
    breadcrumb: (l) => l.reader,
    open: (c) =>
        const ReaderSettingsRoute(highlight: 'showVerticalSeekbar').push(c),
    visible: (ref, _) =>
        !ref.watch(forceHorizontalSeekbarProvider).ifNull(false),
  ),
  SettingsSearchEntry(
    id: 'leftHandedVerticalSeekbar',
    title: (l) => l.leftHandedVerticalSeekbar,
    breadcrumb: (l) => l.reader,
    open: (c) => const ReaderSettingsRoute(
      highlight: 'leftHandedVerticalSeekbar',
    ).push(c),
    visible: (ref, _) =>
        !ref.watch(forceHorizontalSeekbarProvider).ifNull(false),
  ),
  SettingsSearchEntry(
    id: 'readerBackgroundColor',
    title: (l) => l.readerBackgroundColor,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupDisplay}',
    open: (c) => const ReaderSettingsRoute(
      highlight: 'readerBackgroundColor',
    ).push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'readerFullscreen',
    title: (l) => l.readerFullscreen,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupDisplay}',
    open: (c) =>
        const ReaderSettingsRoute(highlight: 'readerFullscreen').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'showContentInCutoutArea',
    title: (l) => l.showContentInCutoutArea,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupDisplay}',
    open: (c) => const ReaderSettingsRoute(
      highlight: 'showContentInCutoutArea',
    ).push(c),
    visible: (ref, _) => ref.watch(readerFullscreenProvider).ifNull(true),
  ),
  SettingsSearchEntry(
    id: 'showPageNumber',
    title: (l) => l.showPageNumber,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupDisplay}',
    open: (c) =>
        const ReaderSettingsRoute(highlight: 'showPageNumber').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'readerOverlay',
    title: (l) => l.readerOverlay,
    subtitle: (l) => l.readerOverlaySubtitle,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupDisplay}',
    open: (c) => const ReaderSettingsRoute(highlight: 'readerOverlay').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'readerPadding',
    title: (l) => l.readerPadding,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupDisplay}',
    open: (c) => const ReaderSettingsRoute(highlight: 'readerPadding').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'keepScreenOn',
    title: (l) => l.readerKeepScreenOn,
    subtitle: (l) => l.readerKeepScreenOnSubtitle,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupDisplay}',
    open: (c) => const ReaderSettingsRoute(highlight: 'keepScreenOn').push(c),
    visible: (_, _) =>
        !kIsWeb && (isAndroidRuntime || Platform.isIOS),
  ),
  SettingsSearchEntry(
    id: 'ignoreSafeArea',
    title: (l) => l.readerIgnoreSafeAreaToggle,
    subtitle: (l) => l.readerIgnoreSafeAreaToggleDescription,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupDisplay}',
    open: (c) =>
        const ReaderSettingsRoute(highlight: 'ignoreSafeArea').push(c),
    visible: (_, _) =>
        !kIsWeb && (isAndroidRuntime || Platform.isIOS),
  ),
  SettingsSearchEntry(
    id: 'flashOnPageChange',
    title: (l) => l.flashOnPageChange,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupEInk}',
    open: (c) =>
        const ReaderSettingsRoute(highlight: 'flashOnPageChange').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'flashDuration',
    title: (l) => l.flashDuration,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupEInk}',
    open: (c) => const ReaderSettingsRoute(highlight: 'flashDuration').push(c),
    visible: (ref, _) => ref.watch(flashOnPageChangeProvider).ifNull(false),
  ),
  SettingsSearchEntry(
    id: 'flashEvery',
    title: (l) => l.flashEvery,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupEInk}',
    open: (c) => const ReaderSettingsRoute(highlight: 'flashEvery').push(c),
    visible: (ref, _) => ref.watch(flashOnPageChangeProvider).ifNull(false),
  ),
  SettingsSearchEntry(
    id: 'flashWith',
    title: (l) => l.flashWith,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupEInk}',
    open: (c) => const ReaderSettingsRoute(highlight: 'flashWith').push(c),
    visible: (ref, _) => ref.watch(flashOnPageChangeProvider).ifNull(false),
  ),
  SettingsSearchEntry(
    id: 'alwaysShowChapterTransition',
    title: (l) => l.alwaysShowChapterTransition,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupReading}',
    open: (c) => const ReaderSettingsRoute(
      highlight: 'alwaysShowChapterTransition',
    ).push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'swipeChapterToggle',
    title: (l) => l.readerSwipeChapterToggle,
    subtitle: (l) => l.readerSwipeChapterToggleDescription,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupReading}',
    open: (c) =>
        const ReaderSettingsRoute(highlight: 'swipeChapterToggle').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'lastPageSwipe',
    title: (l) => l.readerLastPageSwipeToggle,
    subtitle: (l) => l.readerLastPageSwipeToggleDescription,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupReading}',
    open: (c) => const ReaderSettingsRoute(highlight: 'lastPageSwipe').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'scrollAnimation',
    title: (l) => l.readerScrollAnimation,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupReading}',
    open: (c) =>
        const ReaderSettingsRoute(highlight: 'scrollAnimation').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'feedbackToasts',
    title: (l) => l.readerFeedbackToasts,
    subtitle: (l) => l.readerFeedbackToastsSubtitle,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupReading}',
    open: (c) =>
        const ReaderSettingsRoute(highlight: 'feedbackToasts').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'mouseScrollSpeed',
    title: (l) => l.readerMouseScrollSpeed,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupReading}',
    open: (c) =>
        const ReaderSettingsRoute(highlight: 'mouseScrollSpeed').push(c),
    visible: (_, _) => isKeyboardRuntime,
  ),
  SettingsSearchEntry(
    id: 'pagedTapZones',
    title: (l) => l.readerNavigationLayout,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupPagerViewer}',
    open: (c) => const ReaderSettingsRoute(highlight: 'pagedTapZones').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'pagedTapInvert',
    title: (l) => l.readerNavigationLayoutInvert,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupPagerViewer}',
    open: (c) => const ReaderSettingsRoute(highlight: 'pagedTapInvert').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'imageScaleType',
    title: (l) => l.imageScaleType,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupPagerViewer}',
    open: (c) =>
        const ReaderSettingsRoute(highlight: 'imageScaleType').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'pageLayout',
    title: (l) => l.pageLayout,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupPagerViewer}',
    open: (c) => const ReaderSettingsRoute(highlight: 'pageLayout').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'centerMarginType',
    title: (l) => l.centerMarginType,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupPagerViewer}',
    open: (c) =>
        const ReaderSettingsRoute(highlight: 'centerMarginType').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'cropBordersPaged',
    title: (l) => l.cropBorders,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupPagerViewer}',
    open: (c) =>
        const ReaderSettingsRoute(highlight: 'cropBordersPaged').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'splitWidePages',
    title: (l) => l.splitWidePages,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupPagerViewer}',
    open: (c) =>
        const ReaderSettingsRoute(highlight: 'splitWidePages').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'invertSplitPages',
    title: (l) => l.invertSplitPagesPlacement,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupPagerViewer}',
    open: (c) =>
        const ReaderSettingsRoute(highlight: 'invertSplitPages').push(c),
    visible: (ref, _) => ref.watch(dualPageSplitPagedProvider).ifNull(false),
  ),
  SettingsSearchEntry(
    id: 'rotateWidePages',
    title: (l) => l.rotateWidePagesToFit,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupPagerViewer}',
    open: (c) =>
        const ReaderSettingsRoute(highlight: 'rotateWidePages').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'invertWidePageRotation',
    title: (l) => l.invertWidePageRotation,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupPagerViewer}',
    open: (c) => const ReaderSettingsRoute(
      highlight: 'invertWidePageRotation',
    ).push(c),
    visible: (ref, _) => ref.watch(rotateWidePagesProvider).ifNull(false),
  ),
  SettingsSearchEntry(
    id: 'animatePageTransitions',
    title: (l) => l.animatePageTransitions,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupPagerViewer}',
    open: (c) => const ReaderSettingsRoute(
      highlight: 'animatePageTransitions',
    ).push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'invertDoublePages',
    title: (l) => l.invertDoublePages,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupPagerViewer}',
    open: (c) =>
        const ReaderSettingsRoute(highlight: 'invertDoublePages').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'dualPageSpread',
    title: (l) => l.dualPageSpreadInLandscape,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupPagerViewer}',
    open: (c) =>
        const ReaderSettingsRoute(highlight: 'dualPageSpread').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'disableZoomIn',
    title: (l) => l.disableZoomIn,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupPagerViewer}',
    open: (c) => const ReaderSettingsRoute(highlight: 'disableZoomIn').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'pagedDoubleTapToZoom',
    title: (l) => l.doubleTapToZoom,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupPagerViewer}',
    open: (c) =>
        const ReaderSettingsRoute(highlight: 'pagedDoubleTapToZoom').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'pagedPinchToZoom',
    title: (l) => l.pinchToZoom,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupPagerViewer}',
    open: (c) =>
        const ReaderSettingsRoute(highlight: 'pagedPinchToZoom').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'pagedDisableZoomOut',
    title: (l) => l.disableZoomOut,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupPagerViewer}',
    open: (c) =>
        const ReaderSettingsRoute(highlight: 'pagedDisableZoomOut').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'longStripTapZones',
    title: (l) => l.readerNavigationLayout,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupWebtoonViewer}',
    open: (c) =>
        const ReaderSettingsRoute(highlight: 'longStripTapZones').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'longStripTapInvert',
    title: (l) => l.readerNavigationLayoutInvert,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupWebtoonViewer}',
    open: (c) =>
        const ReaderSettingsRoute(highlight: 'longStripTapInvert').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'webtoonScaleType',
    title: (l) => l.webtoonScaleType,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupWebtoonViewer}',
    open: (c) =>
        const ReaderSettingsRoute(highlight: 'webtoonScaleType').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'longStripWidthLimit',
    title: (l) => l.longStripWidthLimit,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupWebtoonViewer}',
    open: (c) =>
        const ReaderSettingsRoute(highlight: 'longStripWidthLimit').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'cropBordersLongStrip',
    title: (l) => l.cropBorders,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupWebtoonViewer}',
    open: (c) =>
        const ReaderSettingsRoute(highlight: 'cropBordersLongStrip').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'longStripDoubleTapToZoom',
    title: (l) => l.doubleTapToZoom,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupWebtoonViewer}',
    open: (c) => const ReaderSettingsRoute(
      highlight: 'longStripDoubleTapToZoom',
    ).push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'longStripPinchToZoom',
    title: (l) => l.pinchToZoom,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupWebtoonViewer}',
    open: (c) =>
        const ReaderSettingsRoute(highlight: 'longStripPinchToZoom').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'longStripDisableZoomOut',
    title: (l) => l.disableZoomOut,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupWebtoonViewer}',
    open: (c) => const ReaderSettingsRoute(
      highlight: 'longStripDisableZoomOut',
    ).push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'volumeTap',
    title: (l) => l.readerVolumeTap,
    subtitle: (l) => l.readerVolumeTapSubtitle,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupNavigation}',
    open: (c) => const ReaderSettingsRoute(highlight: 'volumeTap').push(c),
    visible: (_, _) => !kIsWeb && isAndroidRuntime,
  ),
  SettingsSearchEntry(
    id: 'volumeTapInvert',
    title: (l) => l.readerVolumeTapInvert,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupNavigation}',
    open: (c) =>
        const ReaderSettingsRoute(highlight: 'volumeTapInvert').push(c),
    visible: (ref, _) =>
        !kIsWeb &&
        isAndroidRuntime &&
        ref.watch(volumeTapProvider).ifNull(),
  ),
  SettingsSearchEntry(
    id: 'showActionsOnLongTap',
    title: (l) => l.showActionsOnLongTap,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupActions}',
    open: (c) =>
        const ReaderSettingsRoute(highlight: 'showActionsOnLongTap').push(c),
    visible: (_, _) => true,
  ),
];

/// Every registered entry in result order: General, Appearance, Library,
/// Reader.
List<SettingsSearchEntry> get allSettingsSearchEntries => [
  ...generalSettingsSearchEntries,
  ...appearanceSettingsSearchEntries,
  ...librarySettingsSearchEntries,
  ...readerSettingsSearchEntries,
];
