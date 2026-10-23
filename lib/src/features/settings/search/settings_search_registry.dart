// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../constants/app_distribution.dart';
import '../../../constants/app_theme.dart';
import '../../../graphql/__generated__/schema.graphql.dart';
import '../../../routes/router_config.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/platform/is_android_native.dart';
import '../../../utils/platform/platform_runtime.dart';
import '../../account/data/account_providers.dart';
import '../../account/domain/account_access.dart';
import '../../notifications/controller/notification_settings_providers.dart';
import '../../offline/data/background/catchup_settings.dart';
import '../../offline/data/offline_repository.dart';
import '../controller/server_controller.dart';
import '../presentation/appearance/widgets/app_theme_selector/app_theme_providers.dart';
import '../presentation/appearance/widgets/show_recommendations/show_recommendations_tile.dart';
import '../presentation/backup/data/backup_settings_repository.dart';
import '../presentation/downloads/data/delete_chapters_settings_repository.dart';
import '../presentation/downloads/data/downloads_settings_repository.dart';
import '../presentation/general/timeout_settings/timeout_settings_section.dart';
import '../presentation/koreader_sync/data/koreader_sync_repository.dart';
import '../presentation/reader/widgets/reader_force_horizontal_seekbar_tile/reader_force_horizontal_seekbar_tile.dart';
import '../presentation/reader/widgets/reader_general_prefs/reader_general_prefs.dart';
import '../presentation/reader/widgets/reader_paged_prefs/reader_paged_prefs.dart';
import '../presentation/reader/widgets/reader_volume_tap_tile/reader_volume_tap_tile.dart';
import '../presentation/server/data/server_settings_repository.dart';
import '../presentation/server/data/web_interface_repository.dart';
import '../presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import '../presentation/server/widget/database/data/database_repository.dart';
import '../presentation/server/widget/images/data/images_repository.dart';
import '../presentation/server/widget/misc_settings/data/misc_logs_repository.dart';
import '../presentation/server/widget/opds/data/opds_repository.dart';
import '../presentation/server/widget/webview/data/webview_repository.dart';
import '../presentation/syncyomi/data/syncyomi_settings_provider.dart';
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
/// - Library: the whole list renders inside the server-data branch (same
///   `serverSettings.value != null` gate as the screen), so every entry
///   needs the server reachable. Permission gates only disable the tap, the
///   tile stays on screen, so they add no further gate.
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
    breadcrumb: (l) => l.general,
    open: (c) =>
        const GeneralSettingsRoute(highlight: 'lockToPortrait').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'serverRequestTimeout',
    title: (l) => l.serverRequestTimeout,
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
    visible: (ref, _) => _serverReachable(ref),
  ),
  SettingsSearchEntry(
    id: 'defaultCategory',
    title: (l) => l.defaultCategoryOnAdd,
    breadcrumb: (l) => '${l.library} › ${l.general}',
    open: (c) =>
        const LibrarySettingsRoute(highlight: 'defaultCategory').push(c),
    visible: (ref, _) => _serverReachable(ref),
  ),
  SettingsSearchEntry(
    id: 'refreshChaptersFromSource',
    title: (l) => l.refreshChaptersFromSource,
    subtitle: (l) => l.refreshChaptersFromSourceSubtitle,
    breadcrumb: (l) => '${l.library} › ${l.general}',
    open: (c) => const LibrarySettingsRoute(
      highlight: 'refreshChaptersFromSource',
    ).push(c),
    visible: (ref, _) => _serverReachable(ref),
  ),
  SettingsSearchEntry(
    id: 'persistentSearchBar',
    title: (l) => l.libraryPersistentSearchBar,
    subtitle: (l) => l.libraryPersistentSearchBarSubtitle,
    breadcrumb: (l) => '${l.library} › ${l.general}',
    open: (c) =>
        const LibrarySettingsRoute(highlight: 'persistentSearchBar').push(c),
    visible: (ref, _) => _serverReachable(ref),
  ),
  SettingsSearchEntry(
    id: 'automaticUpdate',
    title: (l) => l.automaticUpdate,
    breadcrumb: (l) => '${l.library} › ${l.globalUpdate}',
    open: (c) =>
        const LibrarySettingsRoute(highlight: 'automaticUpdate').push(c),
    visible: (ref, _) => _serverReachable(ref),
  ),
  SettingsSearchEntry(
    id: 'automaticallyRefreshMetadata',
    title: (l) => l.automaticallyRefreshMetadata,
    subtitle: (l) => l.automaticallyRefreshMetadataSubtitle,
    breadcrumb: (l) => '${l.library} › ${l.globalUpdate}',
    open: (c) => const LibrarySettingsRoute(
      highlight: 'automaticallyRefreshMetadata',
    ).push(c),
    visible: (ref, _) => _serverReachable(ref),
  ),
  SettingsSearchEntry(
    id: 'skipUpdatingEntries',
    title: (l) => l.skipUpdatingEntries,
    breadcrumb: (l) => '${l.library} › ${l.globalUpdate}',
    open: (c) =>
        const LibrarySettingsRoute(highlight: 'skipUpdatingEntries').push(c),
    visible: (ref, _) => _serverReachable(ref),
  ),
  SettingsSearchEntry(
    id: 'updateCategories',
    title: (l) => l.updateCategories,
    breadcrumb: (l) => '${l.library} › ${l.globalUpdate}',
    open: (c) =>
        const LibrarySettingsRoute(highlight: 'updateCategories').push(c),
    visible: (ref, _) => _serverReachable(ref),
  ),
  SettingsSearchEntry(
    id: 'duplicatedEntries',
    title: (l) => l.duplicatedEntries,
    subtitle: (l) => l.duplicatedEntriesSubtitle,
    breadcrumb: (l) => '${l.library} › ${l.globalUpdate}',
    open: (c) =>
        const LibrarySettingsRoute(highlight: 'duplicatedEntries').push(c),
    visible: (ref, _) => _serverReachable(ref),
  ),
  SettingsSearchEntry(
    id: 'chapterSwipeToLeft',
    title: (l) => l.chapterSwipeToLeft,
    breadcrumb: (l) => '${l.library} › ${l.globalUpdate}',
    open: (c) =>
        const LibrarySettingsRoute(highlight: 'chapterSwipeToLeft').push(c),
    visible: (ref, _) => _serverReachable(ref),
  ),
  SettingsSearchEntry(
    id: 'chapterSwipeToRight',
    title: (l) => l.chapterSwipeToRight,
    breadcrumb: (l) => '${l.library} › ${l.globalUpdate}',
    open: (c) =>
        const LibrarySettingsRoute(highlight: 'chapterSwipeToRight').push(c),
    visible: (ref, _) => _serverReachable(ref),
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
    open: (c) =>
        const ReaderSettingsRoute(highlight: 'readerBackgroundColor').push(c),
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
    open: (c) =>
        const ReaderSettingsRoute(highlight: 'showContentInCutoutArea').push(c),
    visible: (ref, _) => ref.watch(readerFullscreenProvider).ifNull(true),
  ),
  SettingsSearchEntry(
    id: 'showPageNumber',
    title: (l) => l.showPageNumber,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupDisplay}',
    open: (c) => const ReaderSettingsRoute(highlight: 'showPageNumber').push(c),
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
    visible: (_, _) => !kIsWeb && (isAndroidRuntime || Platform.isIOS),
  ),
  SettingsSearchEntry(
    id: 'ignoreSafeArea',
    title: (l) => l.readerIgnoreSafeAreaToggle,
    subtitle: (l) => l.readerIgnoreSafeAreaToggleDescription,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupDisplay}',
    open: (c) => const ReaderSettingsRoute(highlight: 'ignoreSafeArea').push(c),
    visible: (_, _) => !kIsWeb && (isAndroidRuntime || Platform.isIOS),
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
    open: (c) => const ReaderSettingsRoute(highlight: 'feedbackToasts').push(c),
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
    open: (c) => const ReaderSettingsRoute(highlight: 'imageScaleType').push(c),
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
    open: (c) => const ReaderSettingsRoute(highlight: 'splitWidePages').push(c),
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
    open: (c) =>
        const ReaderSettingsRoute(highlight: 'invertWidePageRotation').push(c),
    visible: (ref, _) => ref.watch(rotateWidePagesProvider).ifNull(false),
  ),
  SettingsSearchEntry(
    id: 'animatePageTransitions',
    title: (l) => l.animatePageTransitions,
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupPagerViewer}',
    open: (c) =>
        const ReaderSettingsRoute(highlight: 'animatePageTransitions').push(c),
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
    open: (c) => const ReaderSettingsRoute(highlight: 'dualPageSpread').push(c),
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
    open: (c) =>
        const ReaderSettingsRoute(highlight: 'longStripDisableZoomOut').push(c),
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
        !kIsWeb && isAndroidRuntime && ref.watch(volumeTapProvider).ifNull(),
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

/// Browse page (4 rows, plain "Browse" breadcrumb). Show NSFW always renders;
/// the other three only mount while the server settings hold a value (same
/// `serverSettings.value != null` gate as the screen). The permission gate
/// only disables those rows' editors, never unmounts them, so it adds no
/// further gate.
List<SettingsSearchEntry> get browseSettingsSearchEntries => [
  SettingsSearchEntry(
    id: 'showNsfw',
    title: (l) => l.nsfw,
    breadcrumb: (l) => l.browse,
    open: (c) => const BrowseSettingsRoute(highlight: 'showNsfw').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'parallelSourceRequests',
    title: (l) => l.parallelSourceRequest,
    breadcrumb: (l) => l.browse,
    open: (c) =>
        const BrowseSettingsRoute(highlight: 'parallelSourceRequests').push(c),
    visible: (ref, _) => _serverReachable(ref),
  ),
  SettingsSearchEntry(
    id: 'localSourceLocation',
    title: (l) => l.localSourceLocation,
    breadcrumb: (l) => l.browse,
    open: (c) =>
        const BrowseSettingsRoute(highlight: 'localSourceLocation').push(c),
    visible: (ref, _) => _serverReachable(ref),
  ),
  SettingsSearchEntry(
    id: 'extensionStores',
    title: (l) => l.extensionStores,
    breadcrumb: (l) => l.browse,
    open: (c) =>
        const BrowseSettingsRoute(highlight: 'extensionStores').push(c),
    visible: (ref, _) => _serverReachable(ref),
  ),
];

/// Notifications page (9 rows, plain "Notifications" breadcrumb), Android
/// only. The five rows under "New chapter notifications" only render while it
/// is on — same [notificationsNewChaptersEnabledProvider] read as the screen.
/// The rest always render there.
List<SettingsSearchEntry> get notificationsSettingsSearchEntries => [
  SettingsSearchEntry(
    id: 'notificationsNewChapters',
    title: (l) => l.notificationsNewChapters,
    subtitle: (l) => l.notificationsNewChaptersSubtitle,
    breadcrumb: (l) => l.notifications,
    open: (c) => const NotificationsSettingsRoute(
      highlight: 'notificationsNewChapters',
    ).push(c),
    visible: (_, _) => isAndroidNative,
  ),
  SettingsSearchEntry(
    id: 'notificationsCheckInterval',
    title: (l) => l.notificationsCheckInterval,
    breadcrumb: (l) => l.notifications,
    open: (c) => const NotificationsSettingsRoute(
      highlight: 'notificationsCheckInterval',
    ).push(c),
    visible: (ref, _) =>
        isAndroidNative &&
        ref.watch(notificationsNewChaptersEnabledProvider).ifNull(),
  ),
  SettingsSearchEntry(
    id: 'notificationsWifiOnly',
    title: (l) => l.notificationsWifiOnly,
    breadcrumb: (l) => l.notifications,
    open: (c) => const NotificationsSettingsRoute(
      highlight: 'notificationsWifiOnly',
    ).push(c),
    visible: (ref, _) =>
        isAndroidNative &&
        ref.watch(notificationsNewChaptersEnabledProvider).ifNull(),
  ),
  SettingsSearchEntry(
    id: 'notificationsChargingOnly',
    title: (l) => l.notificationsChargingOnly,
    breadcrumb: (l) => l.notifications,
    open: (c) => const NotificationsSettingsRoute(
      highlight: 'notificationsChargingOnly',
    ).push(c),
    visible: (ref, _) =>
        isAndroidNative &&
        ref.watch(notificationsNewChaptersEnabledProvider).ifNull(),
  ),
  SettingsSearchEntry(
    id: 'notificationsHideContent',
    title: (l) => l.notificationsHideContent,
    subtitle: (l) => l.notificationsHideContentSubtitle,
    breadcrumb: (l) => l.notifications,
    open: (c) => const NotificationsSettingsRoute(
      highlight: 'notificationsHideContent',
    ).push(c),
    visible: (ref, _) =>
        isAndroidNative &&
        ref.watch(notificationsNewChaptersEnabledProvider).ifNull(),
  ),
  SettingsSearchEntry(
    id: 'notificationsCheckNow',
    title: (l) => l.notificationsCheckNow,
    breadcrumb: (l) => l.notifications,
    open: (c) => const NotificationsSettingsRoute(
      highlight: 'notificationsCheckNow',
    ).push(c),
    visible: (ref, _) =>
        isAndroidNative &&
        ref.watch(notificationsNewChaptersEnabledProvider).ifNull(),
  ),
  SettingsSearchEntry(
    id: 'notificationsDownloadsComplete',
    title: (l) => l.notificationsDownloadsComplete,
    breadcrumb: (l) => l.notifications,
    open: (c) => const NotificationsSettingsRoute(
      highlight: 'notificationsDownloadsComplete',
    ).push(c),
    visible: (_, _) => isAndroidNative,
  ),
  SettingsSearchEntry(
    id: 'notificationsAppUpdates',
    title: (l) => l.notificationsAppUpdates,
    breadcrumb: (l) => l.notifications,
    open: (c) => const NotificationsSettingsRoute(
      highlight: 'notificationsAppUpdates',
    ).push(c),
    visible: (_, _) => isAndroidNative && !isGooglePlayBuild,
  ),
  SettingsSearchEntry(
    id: 'notificationsExtensionUpdates',
    title: (l) => l.notificationsExtensionUpdates,
    breadcrumb: (l) => l.notifications,
    open: (c) => const NotificationsSettingsRoute(
      highlight: 'notificationsExtensionUpdates',
    ).push(c),
    visible: (_, _) => isAndroidNative,
  ),
];

/// Backup page (6 rows, plain "Backup" breadcrumb). The include-* checkboxes
/// live in the Create Backup dialog, not on the page, so they have no
/// entries. Create/restore always render; the four automatic rows only mount
/// while the server settings hold a value (same `showUiWhenData` data branch
/// as the screen). The permission gate only disables the automatic rows'
/// editors, so it adds no further gate.
List<SettingsSearchEntry> get backupSettingsSearchEntries => [
  SettingsSearchEntry(
    id: 'createBackup',
    title: (l) => l.createBackupTitle,
    breadcrumb: (l) => l.backup,
    open: (c) => const BackupRoute(highlight: 'createBackup').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'restoreBackup',
    title: (l) => l.restoreBackupTitle,
    breadcrumb: (l) => l.backup,
    open: (c) => const BackupRoute(highlight: 'restoreBackup').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'backupLocation',
    title: (l) => l.backupLocation,
    breadcrumb: (l) => l.backup,
    open: (c) => const BackupRoute(highlight: 'backupLocation').push(c),
    visible: (ref, _) => _serverReachable(ref),
  ),
  SettingsSearchEntry(
    id: 'backupData',
    title: (l) => l.backupData,
    breadcrumb: (l) => l.backup,
    open: (c) => const BackupRoute(highlight: 'backupData').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) &&
        ref.watch(autoBackupFlagsProvider).value != null,
  ),
  SettingsSearchEntry(
    id: 'backupTime',
    title: (l) => l.backupTime,
    breadcrumb: (l) => l.backup,
    open: (c) => const BackupRoute(highlight: 'backupTime').push(c),
    visible: (ref, _) => _serverReachable(ref),
  ),
  SettingsSearchEntry(
    id: 'backupInterval',
    title: (l) => l.backupInterval,
    breadcrumb: (l) => l.backup,
    open: (c) => const BackupRoute(highlight: 'backupInterval').push(c),
    visible: (ref, _) => _serverReachable(ref),
  ),
  SettingsSearchEntry(
    id: 'backupCleanup',
    title: (l) => l.backupCleanup,
    breadcrumb: (l) => l.backup,
    open: (c) => const BackupRoute(highlight: 'backupCleanup').push(c),
    visible: (ref, _) => _serverReachable(ref),
  ),
];

/// Downloads page: Server tab (9 rows, tab 0) and On device tab (13 rows,
/// tab 1), with "Downloads › Server" / "Downloads › On device" breadcrumbs.
/// The three delete rows share titles across tabs but carry per-tab ids, so
/// search can land on the right tab's row.
///
/// Server rows only mount while the server settings hold a value (same
/// `showUiWhenData` data branch as the screen); permission/personal gates
/// only disable them, so they add no further gate. Every On device row needs
/// the offline feature enabled
/// (otherwise the tab shows the "not available" note instead). The
/// keep-window switch additionally needs delete-while-reading at 2+, the
/// background switch needs Android-native, and its two sub-rows need the
/// background run switched on — each mirroring the screen's gate exactly.
List<SettingsSearchEntry> get downloadsSettingsSearchEntries => [
  SettingsSearchEntry(
    id: 'downloadLocation',
    title: (l) => l.downloadLocation,
    breadcrumb: (l) => '${l.downloads} › ${l.downloadsServerTab}',
    open: (c) => const DownloadsSettingsRoute(
      highlight: 'downloadLocation',
      tab: 0,
    ).push(c),
    visible: (ref, _) => _serverReachable(ref),
    tabIndex: 0,
  ),
  SettingsSearchEntry(
    id: 'saveAsCbz',
    title: (l) => l.saveAsCBZArchive,
    breadcrumb: (l) => '${l.downloads} › ${l.downloadsServerTab}',
    open: (c) =>
        const DownloadsSettingsRoute(highlight: 'saveAsCbz', tab: 0).push(c),
    visible: (ref, _) => _serverReachable(ref),
    tabIndex: 0,
  ),
  // Same highlight id as the Server › Images row: both open the same editor.
  SettingsSearchEntry(
    id: 'imageDownloadProcessing',
    title: (l) => l.imageDownloadProcessing,
    breadcrumb: (l) => '${l.downloads} › ${l.downloadsServerTab}',
    open: (c) => const DownloadsSettingsRoute(
      highlight: 'imageDownloadProcessing',
      tab: 0,
    ).push(c),
    visible: (ref, _) =>
        _serverReachable(ref) &&
        ref.watch(imagesDownloadSettingsProvider).value != null,
    tabIndex: 0,
  ),
  SettingsSearchEntry(
    id: 'serverDeleteManuallyMarkedRead',
    title: (l) => l.deleteChapterAfterManuallyMarkedRead,
    breadcrumb: (l) => '${l.downloads} › ${l.downloadsServerTab}',
    open: (c) => const DownloadsSettingsRoute(
      highlight: 'serverDeleteManuallyMarkedRead',
      tab: 0,
    ).push(c),
    visible: (ref, _) => _serverReachable(ref),
    tabIndex: 0,
  ),
  SettingsSearchEntry(
    id: 'serverDeleteWhileReading',
    title: (l) => l.deleteFinishedChaptersWhileReading,
    breadcrumb: (l) => '${l.downloads} › ${l.downloadsServerTab}',
    open: (c) => const DownloadsSettingsRoute(
      highlight: 'serverDeleteWhileReading',
      tab: 0,
    ).push(c),
    visible: (ref, _) => _serverReachable(ref),
    tabIndex: 0,
  ),
  SettingsSearchEntry(
    id: 'serverDeleteWithBookmark',
    title: (l) => l.allowDeletingBookmarkedChapters,
    breadcrumb: (l) => '${l.downloads} › ${l.downloadsServerTab}',
    open: (c) => const DownloadsSettingsRoute(
      highlight: 'serverDeleteWithBookmark',
      tab: 0,
    ).push(c),
    visible: (ref, _) => _serverReachable(ref),
    tabIndex: 0,
  ),
  SettingsSearchEntry(
    id: 'autoDownloadNewChapters',
    title: (l) => l.autoDownloadNewChapters,
    breadcrumb: (l) => '${l.downloads} › ${l.downloadsServerTab}',
    open: (c) => const DownloadsSettingsRoute(
      highlight: 'autoDownloadNewChapters',
      tab: 0,
    ).push(c),
    visible: (ref, _) => _serverReachable(ref),
    tabIndex: 0,
  ),
  SettingsSearchEntry(
    id: 'chapterDownloadLimit',
    title: (l) => l.chapterDownloadLimit,
    breadcrumb: (l) => '${l.downloads} › ${l.downloadsServerTab}',
    open: (c) => const DownloadsSettingsRoute(
      highlight: 'chapterDownloadLimit',
      tab: 0,
    ).push(c),
    visible: (ref, _) => _serverReachable(ref),
    tabIndex: 0,
  ),
  SettingsSearchEntry(
    id: 'excludeEntryWithUnreadChapters',
    title: (l) => l.excludeEntryWithUnreadChapters,
    breadcrumb: (l) => '${l.downloads} › ${l.downloadsServerTab}',
    open: (c) => const DownloadsSettingsRoute(
      highlight: 'excludeEntryWithUnreadChapters',
      tab: 0,
    ).push(c),
    visible: (ref, _) => _serverReachable(ref),
    tabIndex: 0,
  ),
  SettingsSearchEntry(
    id: 'ignoreReuploadedChapters',
    title: (l) => l.ignoreReuploadedChapters,
    breadcrumb: (l) => '${l.downloads} › ${l.downloadsServerTab}',
    open: (c) => const DownloadsSettingsRoute(
      highlight: 'ignoreReuploadedChapters',
      tab: 0,
    ).push(c),
    visible: (ref, _) =>
        _serverReachable(ref) &&
        ref.watch(autoDownloadIgnoreReUploadsProvider).value != null,
    tabIndex: 0,
  ),
  SettingsSearchEntry(
    id: 'autoDownloadCategories',
    title: (l) => l.autoDownloadCategories,
    breadcrumb: (l) => '${l.downloads} › ${l.downloadsServerTab}',
    open: (c) => const DownloadsSettingsRoute(
      highlight: 'autoDownloadCategories',
      tab: 0,
    ).push(c),
    visible: (ref, _) => _serverReachable(ref),
    tabIndex: 0,
  ),
  SettingsSearchEntry(
    id: 'deviceDeleteManuallyMarkedRead',
    title: (l) => l.deleteChapterAfterManuallyMarkedRead,
    breadcrumb: (l) => '${l.downloads} › ${l.downloadsOnDeviceTab}',
    open: (c) => const DownloadsSettingsRoute(
      highlight: 'deviceDeleteManuallyMarkedRead',
      tab: 1,
    ).push(c),
    visible: (ref, _) => ref.watch(offlineEnabledProvider),
    tabIndex: 1,
  ),
  SettingsSearchEntry(
    id: 'deviceDeleteWhileReading',
    title: (l) => l.deleteFinishedChaptersWhileReading,
    breadcrumb: (l) => '${l.downloads} › ${l.downloadsOnDeviceTab}',
    open: (c) => const DownloadsSettingsRoute(
      highlight: 'deviceDeleteWhileReading',
      tab: 1,
    ).push(c),
    visible: (ref, _) => ref.watch(offlineEnabledProvider),
    tabIndex: 1,
  ),
  SettingsSearchEntry(
    id: 'deviceDeleteWithBookmark',
    title: (l) => l.allowDeletingBookmarkedChapters,
    breadcrumb: (l) => '${l.downloads} › ${l.downloadsOnDeviceTab}',
    open: (c) => const DownloadsSettingsRoute(
      highlight: 'deviceDeleteWithBookmark',
      tab: 1,
    ).push(c),
    visible: (ref, _) => ref.watch(offlineEnabledProvider),
    tabIndex: 1,
  ),
  SettingsSearchEntry(
    id: 'downloadProtectionWindow',
    title: (l) => l.downloadProtectionWindowTitle,
    subtitle: (l) => l.downloadProtectionWindowDescription,
    breadcrumb: (l) => '${l.downloads} › ${l.downloadsOnDeviceTab}',
    open: (c) => const DownloadsSettingsRoute(
      highlight: 'downloadProtectionWindow',
      tab: 1,
    ).push(c),
    visible: (ref, _) =>
        ref.watch(offlineEnabledProvider) &&
        (ref.watch(localDeleteWhileReadingProvider) ?? 0) >= 2,
    tabIndex: 1,
  ),
  SettingsSearchEntry(
    id: 'removeAllDownloads',
    title: (l) => l.offlineRemoveAllDownloads,
    breadcrumb: (l) => '${l.downloads} › ${l.downloadsOnDeviceTab}',
    open: (c) => const DownloadsSettingsRoute(
      highlight: 'removeAllDownloads',
      tab: 1,
    ).push(c),
    visible: (ref, _) => ref.watch(offlineEnabledProvider),
    tabIndex: 1,
  ),
  SettingsSearchEntry(
    id: 'offlineWifiOnly',
    title: (l) => l.downloadOverWifiOnly,
    breadcrumb: (l) => '${l.downloads} › ${l.downloadsOnDeviceTab}',
    open: (c) => const DownloadsSettingsRoute(
      highlight: 'offlineWifiOnly',
      tab: 1,
    ).push(c),
    visible: (ref, _) => ref.watch(offlineEnabledProvider),
    tabIndex: 1,
  ),
  SettingsSearchEntry(
    id: 'backgroundCatchup',
    title: (l) => l.downloadNewChaptersInBackground,
    subtitle: (l) => l.downloadNewChaptersInBackgroundDescription,
    breadcrumb: (l) => '${l.downloads} › ${l.downloadsOnDeviceTab}',
    open: (c) => const DownloadsSettingsRoute(
      highlight: 'backgroundCatchup',
      tab: 1,
    ).push(c),
    visible: (ref, _) => ref.watch(offlineEnabledProvider) && isAndroidNative,
    tabIndex: 1,
  ),
  SettingsSearchEntry(
    id: 'backgroundCheckInterval',
    title: (l) => l.notificationsCheckInterval,
    breadcrumb: (l) => '${l.downloads} › ${l.downloadsOnDeviceTab}',
    open: (c) => const DownloadsSettingsRoute(
      highlight: 'backgroundCheckInterval',
      tab: 1,
    ).push(c),
    visible: (ref, _) =>
        ref.watch(offlineEnabledProvider) &&
        isAndroidNative &&
        ref.watch(backgroundCatchupEnabledProvider),
    tabIndex: 1,
  ),
  SettingsSearchEntry(
    id: 'backgroundFetchFiles',
    title: (l) => l.backgroundCatchupFetchFiles,
    subtitle: (l) => l.backgroundCatchupFetchFilesDescription,
    breadcrumb: (l) => '${l.downloads} › ${l.downloadsOnDeviceTab}',
    open: (c) => const DownloadsSettingsRoute(
      highlight: 'backgroundFetchFiles',
      tab: 1,
    ).push(c),
    visible: (ref, _) =>
        ref.watch(offlineEnabledProvider) &&
        isAndroidNative &&
        ref.watch(backgroundCatchupEnabledProvider),
    tabIndex: 1,
  ),
  SettingsSearchEntry(
    id: 'offlineConcurrency',
    title: (l) => l.offlineConcurrencyLabel,
    breadcrumb: (l) => '${l.downloads} › ${l.downloadsOnDeviceTab}',
    open: (c) => const DownloadsSettingsRoute(
      highlight: 'offlineConcurrency',
      tab: 1,
    ).push(c),
    visible: (ref, _) => ref.watch(offlineEnabledProvider),
    tabIndex: 1,
  ),
  SettingsSearchEntry(
    id: 'offlineStorageCapEnable',
    title: (l) => l.offlineStorageCapEnable,
    breadcrumb: (l) => '${l.downloads} › ${l.downloadsOnDeviceTab}',
    open: (c) => const DownloadsSettingsRoute(
      highlight: 'offlineStorageCapEnable',
      tab: 1,
    ).push(c),
    visible: (ref, _) => ref.watch(offlineEnabledProvider),
    tabIndex: 1,
  ),
  SettingsSearchEntry(
    id: 'offlineStorageCapLimit',
    title: (l) => l.offlineStorageCapLimit,
    breadcrumb: (l) => '${l.downloads} › ${l.downloadsOnDeviceTab}',
    open: (c) => const DownloadsSettingsRoute(
      highlight: 'offlineStorageCapLimit',
      tab: 1,
    ).push(c),
    visible: (ref, _) => ref.watch(offlineEnabledProvider),
    tabIndex: 1,
  ),
  SettingsSearchEntry(
    id: 'offlineTimeEvictEnable',
    title: (l) => l.offlineTimeEvictEnable,
    breadcrumb: (l) => '${l.downloads} › ${l.downloadsOnDeviceTab}',
    open: (c) => const DownloadsSettingsRoute(
      highlight: 'offlineTimeEvictEnable',
      tab: 1,
    ).push(c),
    visible: (ref, _) => ref.watch(offlineEnabledProvider),
    tabIndex: 1,
  ),
  SettingsSearchEntry(
    id: 'offlineKeepDays',
    title: (l) => l.offlineKeepDaysLabel,
    breadcrumb: (l) => '${l.downloads} › ${l.downloadsOnDeviceTab}',
    open: (c) => const DownloadsSettingsRoute(
      highlight: 'offlineKeepDays',
      tab: 1,
    ).push(c),
    visible: (ref, _) => ref.watch(offlineEnabledProvider),
    tabIndex: 1,
  ),
];

/// Server page (17 rows, "Server › \<Section\>" breadcrumbs with the real
/// section header strings). The whole page is server state: every entry needs
/// the server reachable (`settingsProvider` holding a value — loading/error
/// shows the fallback view instead), which subsumes each section's own
/// `serverSettings.value != null` gate. Web-interface rows additionally need
/// the web settings loaded and MANAGE_SETTINGS (both gate the tiles'
/// mounting, unlike the permission-gated-but-mounted rows elsewhere); the
/// channel/automatic rows stay mounted-but-disabled under the Custom flavor,
/// so they stay visible. Check for update needs an authenticated session
/// and a non-Custom flavor, exactly like its tile. SOCKS rows need the
/// proxy on, FlareSolverr rows need it on — same DTO flags as the screen.
/// "Installed version" is read-only info with no editor, so it has no entry.
bool _serverReachable(WidgetRef ref) =>
    ref.watch(settingsProvider).value != null;

bool _webInterfaceVisible(WidgetRef ref) =>
    _serverReachable(ref) &&
    ref
        .watch(settledAccountAccessProvider)
        .allows(Enum$UserPermission.MANAGE_SETTINGS) &&
    ref.watch(webInterfaceSettingsProvider).value != null;

List<SettingsSearchEntry> get serverSettingsSearchEntries => [
  SettingsSearchEntry(
    id: 'webInterfaceFlavor',
    title: (l) => l.webInterfaceInterface,
    breadcrumb: (l) => '${l.server} › ${l.webInterface}',
    open: (c) =>
        const ServerSettingsRoute(highlight: 'webInterfaceFlavor').push(c),
    visible: (ref, _) => _webInterfaceVisible(ref),
  ),
  SettingsSearchEntry(
    id: 'initialOpenInBrowserEnabled',
    title: (l) => l.initialOpenInBrowserEnabled,
    breadcrumb: (l) => '${l.server} › ${l.webInterface}',
    open: (c) => const ServerSettingsRoute(
      highlight: 'initialOpenInBrowserEnabled',
    ).push(c),
    visible: (ref, _) => _webInterfaceVisible(ref),
  ),
  SettingsSearchEntry(
    id: 'webInterfaceInterface',
    title: (l) => l.webInterfaceOpenWith,
    breadcrumb: (l) => '${l.server} › ${l.webInterface}',
    open: (c) => const ServerSettingsRoute(
      highlight: 'webInterfaceInterface',
    ).push(c),
    visible: (ref, _) => _webInterfaceVisible(ref),
  ),
  SettingsSearchEntry(
    id: 'electronPath',
    title: (l) => l.electronPath,
    breadcrumb: (l) => '${l.server} › ${l.webInterface}',
    open: (c) =>
        const ServerSettingsRoute(highlight: 'electronPath').push(c),
    visible: (ref, _) =>
        _webInterfaceVisible(ref) &&
        ref.watch(webInterfaceSettingsProvider).value?.webUIInterface ==
            Enum$WebUIInterface.ELECTRON,
  ),
  SettingsSearchEntry(
    id: 'webInterfaceChannel',
    title: (l) => l.webInterfaceChannel,
    breadcrumb: (l) => '${l.server} › ${l.webInterface}',
    open: (c) =>
        const ServerSettingsRoute(highlight: 'webInterfaceChannel').push(c),
    visible: (ref, _) => _webInterfaceVisible(ref),
  ),
  SettingsSearchEntry(
    id: 'webInterfaceAutomaticUpdates',
    title: (l) => l.webInterfaceAutomaticUpdates,
    breadcrumb: (l) => '${l.server} › ${l.webInterface}',
    open: (c) => const ServerSettingsRoute(
      highlight: 'webInterfaceAutomaticUpdates',
    ).push(c),
    visible: (ref, _) => _webInterfaceVisible(ref),
  ),
  SettingsSearchEntry(
    id: 'webInterfaceCheckUpdate',
    title: (l) => l.webInterfaceCheckUpdate,
    breadcrumb: (l) => '${l.server} › ${l.webInterface}',
    open: (c) =>
        const ServerSettingsRoute(highlight: 'webInterfaceCheckUpdate').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) &&
        ref.watch(settledAccountAccessProvider).capability !=
            AccountCapability.unknown &&
        ref.watch(webInterfaceSettingsProvider).value?.webUIFlavor !=
            Enum$WebUIFlavor.CUSTOM,
  ),
  SettingsSearchEntry(
    id: 'serverIpAddress',
    title: (l) => l.ip,
    breadcrumb: (l) => '${l.server} › ${l.serverBindings}',
    open: (c) =>
        const ServerSettingsRoute(highlight: 'serverIpAddress').push(c),
    visible: (ref, _) => _serverReachable(ref),
  ),
  SettingsSearchEntry(
    id: 'serverPort',
    title: (l) => l.serverPort,
    breadcrumb: (l) => '${l.server} › ${l.serverBindings}',
    open: (c) => const ServerSettingsRoute(highlight: 'serverPort').push(c),
    visible: (ref, _) => _serverReachable(ref),
  ),
  SettingsSearchEntry(
    id: 'enableSocksProxy',
    title: (l) => l.enableSocksProxy,
    breadcrumb: (l) => '${l.server} › ${l.socksProxy}',
    open: (c) =>
        const ServerSettingsRoute(highlight: 'enableSocksProxy').push(c),
    visible: (ref, _) => _serverReachable(ref),
  ),
  SettingsSearchEntry(
    id: 'socksVersion',
    title: (l) => l.socksVersion,
    breadcrumb: (l) => '${l.server} › ${l.socksProxy}',
    open: (c) => const ServerSettingsRoute(highlight: 'socksVersion').push(c),
    visible: (ref, _) =>
        ref.watch(settingsProvider).value?.socksProxyEnabled ?? false,
  ),
  SettingsSearchEntry(
    id: 'socksHost',
    title: (l) => l.socksHost,
    breadcrumb: (l) => '${l.server} › ${l.socksProxy}',
    open: (c) => const ServerSettingsRoute(highlight: 'socksHost').push(c),
    visible: (ref, _) =>
        ref.watch(settingsProvider).value?.socksProxyEnabled ?? false,
  ),
  SettingsSearchEntry(
    id: 'socksPort',
    title: (l) => l.socksPort,
    breadcrumb: (l) => '${l.server} › ${l.socksProxy}',
    open: (c) => const ServerSettingsRoute(highlight: 'socksPort').push(c),
    visible: (ref, _) =>
        ref.watch(settingsProvider).value?.socksProxyEnabled ?? false,
  ),
  SettingsSearchEntry(
    id: 'socksUserName',
    title: (l) => l.socksUserName,
    breadcrumb: (l) => '${l.server} › ${l.socksProxy}',
    open: (c) => const ServerSettingsRoute(highlight: 'socksUserName').push(c),
    visible: (ref, _) =>
        ref.watch(settingsProvider).value?.socksProxyEnabled ?? false,
  ),
  SettingsSearchEntry(
    id: 'socksPassword',
    title: (l) => l.socksPassword,
    breadcrumb: (l) => '${l.server} › ${l.socksProxy}',
    open: (c) => const ServerSettingsRoute(highlight: 'socksPassword').push(c),
    visible: (ref, _) =>
        ref.watch(settingsProvider).value?.socksProxyEnabled ?? false,
  ),
  SettingsSearchEntry(
    id: 'flareSolverr',
    title: (l) => l.flareSolverr,
    subtitle: (l) => l.openFlareSolverr,
    breadcrumb: (l) => '${l.server} › ${l.cloudflareBypass}',
    open: (c) => const ServerSettingsRoute(highlight: 'flareSolverr').push(c),
    visible: (ref, _) => _serverReachable(ref),
  ),
  SettingsSearchEntry(
    id: 'flareSolverrServerUrl',
    title: (l) => l.flareSolverrServerUrl,
    breadcrumb: (l) => '${l.server} › ${l.cloudflareBypass}',
    open: (c) =>
        const ServerSettingsRoute(highlight: 'flareSolverrServerUrl').push(c),
    visible: (ref, _) =>
        ref.watch(settingsProvider).value?.flareSolverrEnabled ?? false,
  ),
  SettingsSearchEntry(
    id: 'flareSolverrRequestTimeout',
    title: (l) => l.flareSolverrRequestTimeout,
    breadcrumb: (l) => '${l.server} › ${l.cloudflareBypass}',
    open: (c) => const ServerSettingsRoute(
      highlight: 'flareSolverrRequestTimeout',
    ).push(c),
    visible: (ref, _) =>
        ref.watch(settingsProvider).value?.flareSolverrEnabled ?? false,
  ),
  SettingsSearchEntry(
    id: 'flareSolverrSessionName',
    title: (l) => l.flareSolverrSessionName,
    breadcrumb: (l) => '${l.server} › ${l.cloudflareBypass}',
    open: (c) =>
        const ServerSettingsRoute(highlight: 'flareSolverrSessionName').push(c),
    visible: (ref, _) =>
        ref.watch(settingsProvider).value?.flareSolverrEnabled ?? false,
  ),
  SettingsSearchEntry(
    id: 'flareSolverrSessionTTL',
    title: (l) => l.flareSolverrSessionTTL,
    breadcrumb: (l) => '${l.server} › ${l.cloudflareBypass}',
    open: (c) =>
        const ServerSettingsRoute(highlight: 'flareSolverrSessionTTL').push(c),
    visible: (ref, _) =>
        ref.watch(settingsProvider).value?.flareSolverrEnabled ?? false,
  ),
  SettingsSearchEntry(
    id: 'flareSolverrResponseFallback',
    title: (l) => l.responseFallback,
    subtitle: (l) => l.responseFallbackDescription,
    breadcrumb: (l) => '${l.server} › ${l.cloudflareBypass}',
    open: (c) => const ServerSettingsRoute(
      highlight: 'flareSolverrResponseFallback',
    ).push(c),
    visible: (ref, _) =>
        (ref.watch(settingsProvider).value?.flareSolverrEnabled ?? false) &&
        ref.watch(flareSolverrFallbackProvider).value != null,
  ),
  SettingsSearchEntry(
    id: 'opdsBinaryFileSize',
    title: (l) => l.opdsBinaryFileSize,
    subtitle: (l) => l.opdsBinaryFileSizeDescription,
    breadcrumb: (l) => '${l.server} › ${l.opds}',
    open: (c) =>
        const ServerSettingsRoute(highlight: 'opdsBinaryFileSize').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) && ref.watch(opdsSettingsProvider).value != null,
  ),
  SettingsSearchEntry(
    id: 'opdsItemsPerPage',
    title: (l) => l.opdsItemsPerPage,
    subtitle: (l) => l.opdsItemsPerPageDescription,
    breadcrumb: (l) => '${l.server} › ${l.opds}',
    open: (c) =>
        const ServerSettingsRoute(highlight: 'opdsItemsPerPage').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) && ref.watch(opdsSettingsProvider).value != null,
  ),
  SettingsSearchEntry(
    id: 'opdsEnablePageReadProgress',
    title: (l) => l.opdsEnablePageReadProgress,
    subtitle: (l) => l.opdsEnablePageReadProgressDescription,
    breadcrumb: (l) => '${l.server} › ${l.opds}',
    open: (c) => const ServerSettingsRoute(
      highlight: 'opdsEnablePageReadProgress',
    ).push(c),
    visible: (ref, _) =>
        _serverReachable(ref) && ref.watch(opdsSettingsProvider).value != null,
  ),
  SettingsSearchEntry(
    id: 'opdsMarkAsReadOnDownload',
    title: (l) => l.opdsMarkAsReadOnDownload,
    subtitle: (l) => l.opdsMarkAsReadOnDownloadDescription,
    breadcrumb: (l) => '${l.server} › ${l.opds}',
    open: (c) => const ServerSettingsRoute(
      highlight: 'opdsMarkAsReadOnDownload',
    ).push(c),
    visible: (ref, _) =>
        _serverReachable(ref) && ref.watch(opdsSettingsProvider).value != null,
  ),
  SettingsSearchEntry(
    id: 'opdsShowOnlyUnreadChapters',
    title: (l) => l.opdsShowOnlyUnreadChapters,
    subtitle: (l) => l.opdsShowOnlyUnreadChaptersDescription,
    breadcrumb: (l) => '${l.server} › ${l.opds}',
    open: (c) => const ServerSettingsRoute(
      highlight: 'opdsShowOnlyUnreadChapters',
    ).push(c),
    visible: (ref, _) =>
        _serverReachable(ref) && ref.watch(opdsSettingsProvider).value != null,
  ),
  SettingsSearchEntry(
    id: 'opdsShowOnlyDownloadedChapters',
    title: (l) => l.opdsShowOnlyDownloadedChapters,
    subtitle: (l) => l.opdsShowOnlyDownloadedChaptersDescription,
    breadcrumb: (l) => '${l.server} › ${l.opds}',
    open: (c) => const ServerSettingsRoute(
      highlight: 'opdsShowOnlyDownloadedChapters',
    ).push(c),
    visible: (ref, _) =>
        _serverReachable(ref) && ref.watch(opdsSettingsProvider).value != null,
  ),
  SettingsSearchEntry(
    id: 'opdsSkipChapterMetadataFeed',
    title: (l) => l.opdsSkipChapterMetadataFeed,
    subtitle: (l) => l.opdsSkipChapterMetadataFeedDescription,
    breadcrumb: (l) => '${l.server} › ${l.opds}',
    open: (c) => const ServerSettingsRoute(
      highlight: 'opdsSkipChapterMetadataFeed',
    ).push(c),
    visible: (ref, _) =>
        _serverReachable(ref) && ref.watch(opdsSettingsProvider).value != null,
  ),
  SettingsSearchEntry(
    id: 'opdsChapterSortOrder',
    title: (l) => l.opdsChapterSortOrder,
    breadcrumb: (l) => '${l.server} › ${l.opds}',
    open: (c) =>
        const ServerSettingsRoute(highlight: 'opdsChapterSortOrder').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) && ref.watch(opdsSettingsProvider).value != null,
  ),
  SettingsSearchEntry(
    id: 'opdsCbzMimetype',
    title: (l) => l.opdsCbzMimeType,
    breadcrumb: (l) => '${l.server} › ${l.opds}',
    open: (c) =>
        const ServerSettingsRoute(highlight: 'opdsCbzMimetype').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) && ref.watch(opdsSettingsProvider).value != null,
  ),
  SettingsSearchEntry(
    id: 'databaseType',
    title: (l) => l.databaseType,
    breadcrumb: (l) => '${l.server} › ${l.database}',
    open: (c) =>
        const ServerSettingsRoute(highlight: 'databaseType').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) &&
        ref.watch(databaseSettingsProvider).value != null,
  ),
  SettingsSearchEntry(
    id: 'databaseUrl',
    title: (l) => l.databaseUrl,
    breadcrumb: (l) => '${l.server} › ${l.database}',
    open: (c) =>
        const ServerSettingsRoute(highlight: 'databaseUrl').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) &&
        ref.watch(databaseSettingsProvider).value != null,
  ),
  SettingsSearchEntry(
    id: 'databaseUsername',
    title: (l) => l.databaseUsername,
    breadcrumb: (l) => '${l.server} › ${l.database}',
    open: (c) =>
        const ServerSettingsRoute(highlight: 'databaseUsername').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) &&
        ref.watch(databaseSettingsProvider).value != null,
  ),
  SettingsSearchEntry(
    id: 'databasePassword',
    title: (l) => l.databasePassword,
    breadcrumb: (l) => '${l.server} › ${l.database}',
    open: (c) =>
        const ServerSettingsRoute(highlight: 'databasePassword').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) &&
        ref.watch(databaseSettingsProvider).value != null,
  ),
  SettingsSearchEntry(
    id: 'hikariConnectionPool',
    title: (l) => l.hikariConnectionPool,
    subtitle: (l) => l.hikariConnectionPoolDescription,
    breadcrumb: (l) => '${l.server} › ${l.database}',
    open: (c) => const ServerSettingsRoute(
      highlight: 'hikariConnectionPool',
    ).push(c),
    visible: (ref, _) =>
        _serverReachable(ref) &&
        ref.watch(databaseSettingsProvider).value != null,
  ),
  SettingsSearchEntry(
    id: 'webview',
    title: (l) => l.kcefWebView,
    subtitle: (l) => l.kcefWebViewDescription,
    breadcrumb: (l) => '${l.server} › ${l.kcefWebView}',
    open: (c) => const ServerSettingsRoute(highlight: 'webview').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) &&
        ref.watch(webViewSettingsProvider).value != null,
  ),
  SettingsSearchEntry(
    id: 'clearWebViewCache',
    title: (l) => l.clearCookiesAndCache,
    breadcrumb: (l) => '${l.server} › ${l.kcefWebView}',
    open: (c) =>
        const ServerSettingsRoute(highlight: 'clearWebViewCache').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) &&
        (ref.watch(clearCookiesAndCacheSupportProvider).value ?? false),
  ),
  SettingsSearchEntry(
    id: 'imagesClearCache',
    title: (l) => l.imageProcessingClearCache,
    breadcrumb: (l) => '${l.server} › ${l.images}',
    open: (c) =>
        const ServerSettingsRoute(highlight: 'imagesClearCache').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) &&
        (ref.watch(clearCachedImagesSupportProvider).value ?? false),
  ),
  SettingsSearchEntry(
    id: 'imageDownloadProcessing',
    title: (l) => l.imageDownloadProcessing,
    breadcrumb: (l) => '${l.server} › ${l.images}',
    open: (c) => const ServerSettingsRoute(
      highlight: 'imageDownloadProcessing',
    ).push(c),
    visible: (ref, _) =>
        _serverReachable(ref) &&
        ref.watch(imagesDownloadSettingsProvider).value != null,
  ),
  SettingsSearchEntry(
    id: 'imageServeProcessing',
    title: (l) => l.imageServeProcessing,
    breadcrumb: (l) => '${l.server} › ${l.images}',
    open: (c) =>
        const ServerSettingsRoute(highlight: 'imageServeProcessing').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) &&
        ref.watch(serveConversionsProvider).value != null,
  ),
  SettingsSearchEntry(
    id: 'debugLogs',
    title: (l) => l.debugLogs,
    breadcrumb: (l) => '${l.server} › ${l.misc}',
    open: (c) => const ServerSettingsRoute(highlight: 'debugLogs').push(c),
    visible: (ref, _) => _serverReachable(ref),
  ),
  SettingsSearchEntry(
    id: 'systemTrayIcon',
    title: (l) => l.systemTrayIcon,
    breadcrumb: (l) => '${l.server} › ${l.misc}',
    open: (c) => const ServerSettingsRoute(highlight: 'systemTrayIcon').push(c),
    visible: (ref, _) => _serverReachable(ref),
  ),
  SettingsSearchEntry(
    id: 'logFileCleanup',
    title: (l) => l.logFileCleanup,
    breadcrumb: (l) => '${l.server} › ${l.misc}',
    open: (c) =>
        const ServerSettingsRoute(highlight: 'logFileCleanup').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) &&
        ref.watch(miscLogsSettingsProvider).value != null,
  ),
  SettingsSearchEntry(
    id: 'maxLogFileSize',
    title: (l) => l.maxLogFileSize,
    subtitle: (l) => l.logSizeExamples,
    breadcrumb: (l) => '${l.server} › ${l.misc}',
    open: (c) =>
        const ServerSettingsRoute(highlight: 'maxLogFileSize').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) &&
        ref.watch(miscLogsSettingsProvider).value != null,
  ),
  SettingsSearchEntry(
    id: 'maxLogFolderSize',
    title: (l) => l.maxLogFolderSize,
    subtitle: (l) => l.logSizeExamples,
    breadcrumb: (l) => '${l.server} › ${l.misc}',
    open: (c) =>
        const ServerSettingsRoute(highlight: 'maxLogFolderSize').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) &&
        ref.watch(miscLogsSettingsProvider).value != null,
  ),
];

/// Connection page (5 rows, plain "Connection" breadcrumb). Server URL and
/// the auth-mode dropdown always render; the LAN tile only once an address
/// exists (the "add" row is a button, not a setting); the custom-headers
/// entry lands on the section's Add row (per-header rows are dynamic, not
/// settings); Open in WEB is desktop-only, like its tile. Username/password
/// fields, sign-in/test/log-out buttons, chips, and warnings are credentials
/// or transient state, so they have no entries.
List<SettingsSearchEntry> get connectionSettingsSearchEntries => [
  SettingsSearchEntry(
    id: 'serverUrl',
    title: (l) => l.serverUrl,
    breadcrumb: (l) => l.connection,
    open: (c) => const ConnectionRoute(highlight: 'serverUrl').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'serverLanUrl',
    title: (l) => l.serverLanUrl,
    breadcrumb: (l) => l.connection,
    open: (c) => const ConnectionRoute(highlight: 'serverLanUrl').push(c),
    visible: (ref, _) => ref.watch(serverLanUrlProvider) != null,
  ),
  SettingsSearchEntry(
    id: 'authentication',
    title: (l) => l.authType,
    breadcrumb: (l) => l.connection,
    open: (c) => const ConnectionRoute(highlight: 'authentication').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'customHeaders',
    title: (l) => l.customHeaders,
    breadcrumb: (l) => l.connection,
    open: (c) => const ConnectionRoute(highlight: 'customHeaders').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'openInWeb',
    title: (l) => l.webUI,
    breadcrumb: (l) => l.connection,
    open: (c) => const ConnectionRoute(highlight: 'openInWeb').push(c),
    visible: (_, _) => !kIsWeb,
  ),
];

/// SyncYomi page (6 rows, plain "SyncYomi" breadcrumb). Null settings mean
/// the server doesn't support it (the unsupported note shows instead), so
/// nothing is visible then; loading/error likewise hides everything. Sync
/// now additionally needs the triple the screen's section gates on: the
/// switch on plus a non-blank host and API key.
bool _syncYomiSupported(WidgetRef ref) =>
    ref.watch(syncYomiSettingsProvider).value != null;

List<SettingsSearchEntry> get syncYomiSettingsSearchEntries => [
  SettingsSearchEntry(
    id: 'syncYomiEnabled',
    title: (l) => l.syncYomiEnabled,
    breadcrumb: (l) => l.syncyomi,
    open: (c) =>
        const SyncYomiSettingsRoute(highlight: 'syncYomiEnabled').push(c),
    visible: (ref, _) => _syncYomiSupported(ref),
  ),
  SettingsSearchEntry(
    id: 'syncYomiHost',
    title: (l) => l.syncYomiHost,
    breadcrumb: (l) => l.syncyomi,
    open: (c) => const SyncYomiSettingsRoute(highlight: 'syncYomiHost').push(c),
    visible: (ref, _) => _syncYomiSupported(ref),
  ),
  SettingsSearchEntry(
    id: 'syncYomiApiKey',
    title: (l) => l.syncYomiApiKey,
    breadcrumb: (l) => l.syncyomi,
    open: (c) =>
        const SyncYomiSettingsRoute(highlight: 'syncYomiApiKey').push(c),
    visible: (ref, _) => _syncYomiSupported(ref),
  ),
  SettingsSearchEntry(
    id: 'syncYomiSyncInterval',
    title: (l) => l.syncYomiSyncInterval,
    breadcrumb: (l) => l.syncyomi,
    open: (c) =>
        const SyncYomiSettingsRoute(highlight: 'syncYomiSyncInterval').push(c),
    visible: (ref, _) => _syncYomiSupported(ref),
  ),
  SettingsSearchEntry(
    id: 'syncYomiSyncData',
    title: (l) => l.syncYomiSyncData,
    breadcrumb: (l) => l.syncyomi,
    open: (c) =>
        const SyncYomiSettingsRoute(highlight: 'syncYomiSyncData').push(c),
    visible: (ref, _) => _syncYomiSupported(ref),
  ),
  SettingsSearchEntry(
    id: 'syncYomiSyncNow',
    title: (l) => l.syncYomiSyncNow,
    breadcrumb: (l) => l.syncyomi,
    open: (c) =>
        const SyncYomiSettingsRoute(highlight: 'syncYomiSyncNow').push(c),
    visible: (ref, _) {
      final settings = ref.watch(syncYomiSettingsProvider).value;
      return settings != null &&
          settings.enabled &&
          settings.host.isNotBlank &&
          settings.apiKey.isNotBlank;
    },
  ),
];

/// KOReader page (5 rows, plain "KOReader Sync" breadcrumb). Same
/// unsupported rule as the screen: the list only renders when both the
/// server settings and the KOReader status hold values (a null server, a
/// still-loading/error status, or the undefined-field status error all show
/// the unsupported note instead), so every entry needs both.
bool _koreaderSyncSupported(WidgetRef ref) =>
    ref.watch(koreaderSyncSettingsProvider).value != null &&
    ref.watch(koSyncStatusProvider).value != null;

List<SettingsSearchEntry> get koreaderSyncSettingsSearchEntries => [
  SettingsSearchEntry(
    id: 'koreaderSyncStatus',
    title: (l) => l.koreaderSyncStatus,
    breadcrumb: (l) => l.koreaderSync,
    open: (c) => const KoreaderSyncSettingsRoute(
      highlight: 'koreaderSyncStatus',
    ).push(c),
    visible: (ref, _) => _koreaderSyncSupported(ref),
  ),
  SettingsSearchEntry(
    id: 'koreaderSyncStrategyForward',
    title: (l) => l.koreaderSyncStrategyForward,
    breadcrumb: (l) => l.koreaderSync,
    open: (c) => const KoreaderSyncSettingsRoute(
      highlight: 'koreaderSyncStrategyForward',
    ).push(c),
    visible: (ref, _) => _koreaderSyncSupported(ref),
  ),
  SettingsSearchEntry(
    id: 'koreaderSyncStrategyBackward',
    title: (l) => l.koreaderSyncStrategyBackward,
    breadcrumb: (l) => l.koreaderSync,
    open: (c) => const KoreaderSyncSettingsRoute(
      highlight: 'koreaderSyncStrategyBackward',
    ).push(c),
    visible: (ref, _) => _koreaderSyncSupported(ref),
  ),
  SettingsSearchEntry(
    id: 'koreaderSyncChecksumMethod',
    title: (l) => l.koreaderSyncChecksumMethod,
    breadcrumb: (l) => l.koreaderSync,
    open: (c) => const KoreaderSyncSettingsRoute(
      highlight: 'koreaderSyncChecksumMethod',
    ).push(c),
    visible: (ref, _) => _koreaderSyncSupported(ref),
  ),
  SettingsSearchEntry(
    id: 'koreaderSyncPercentageTolerance',
    title: (l) => l.koreaderSyncPercentageTolerance,
    breadcrumb: (l) => l.koreaderSync,
    open: (c) => const KoreaderSyncSettingsRoute(
      highlight: 'koreaderSyncPercentageTolerance',
    ).push(c),
    visible: (ref, _) => _koreaderSyncSupported(ref),
  ),
];

/// Tracking page (2 rows, plain "Tracking" breadcrumb). Both switches render
/// unconditionally; the per-tracker login rows are dynamic server data, not
/// settings, so they have no entries.
List<SettingsSearchEntry> get trackingSettingsSearchEntries => [
  SettingsSearchEntry(
    id: 'updateProgressAfterReading',
    title: (l) => l.updateProgressAfterReading,
    breadcrumb: (l) => l.tracking,
    open: (c) => const TrackingSettingsRoute(
      highlight: 'updateProgressAfterReading',
    ).push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'updateProgressManualMarkRead',
    title: (l) => l.updateProgressManualMarkRead,
    subtitle: (l) => l.updateProgressManualMarkReadDesc,
    breadcrumb: (l) => l.tracking,
    open: (c) => const TrackingSettingsRoute(
      highlight: 'updateProgressManualMarkRead',
    ).push(c),
    visible: (_, _) => true,
  ),
];

/// Holds every GraphQL-backed provider settings search reads for the
/// duration of the open search. Each entry's [SettingsSearchEntry.visible]
/// watches only the providers its own gate needs, and matching stops after
/// [kSettingsSearchLimit] hits — so without this, a query that matches ten
/// local rows first drops every server subscription, the autoDispose
/// providers tear down, and the next keystroke fires a fresh network request
/// per provider. Every search host calls this once per build (above the
/// match call), so typing reuses the in-flight values: at most one fetch per
/// provider while the search is open, and none when the data is already
/// loaded. [syncYomiSettingsProvider] is keepAlive today and is listed too,
/// so the set stays complete if its disposal ever changes.
void pinSettingsSearchProviders(WidgetRef ref) {
  ref.watch(settingsProvider);
  ref.watch(webInterfaceSettingsProvider);
  ref.watch(syncYomiSettingsProvider);
  ref.watch(koreaderSyncSettingsProvider);
  ref.watch(koSyncStatusProvider);
}

/// Every registered entry in result order: General, Appearance, Library,
/// Reader, Browse, Notifications, Backup, Downloads, Server, Connection,
/// SyncYomi, KOReader, Tracking.
List<SettingsSearchEntry> get allSettingsSearchEntries => [
  ...generalSettingsSearchEntries,
  ...appearanceSettingsSearchEntries,
  ...librarySettingsSearchEntries,
  ...readerSettingsSearchEntries,
  ...browseSettingsSearchEntries,
  ...notificationsSettingsSearchEntries,
  ...backupSettingsSearchEntries,
  ...downloadsSettingsSearchEntries,
  ...serverSettingsSearchEntries,
  ...connectionSettingsSearchEntries,
  ...syncYomiSettingsSearchEntries,
  ...koreaderSyncSettingsSearchEntries,
  ...trackingSettingsSearchEntries,
];
