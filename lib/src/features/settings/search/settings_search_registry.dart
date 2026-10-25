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
import '../../../constants/enum.dart';
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
import '../presentation/backup/widgets/backup_flags/backup_flags_dialog.dart';
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
import '../presentation/server/widget/sign_in/data/sign_in_repository.dart';
import '../presentation/server/widget/sign_in/sign_in_section.dart';
import '../presentation/server/widget/webview/data/webview_repository.dart';
import '../presentation/syncyomi/data/syncyomi_settings_provider.dart';
import '../widgets/app_theme_mode_tile/app_theme_mode_tile.dart';
import 'settings_search_entry.dart';

export 'settings_highlight_target.dart';
export 'settings_search_entry.dart';
export 'settings_search_row.dart';

/// Visibility gates must match tile mounting; register entries and highlight targets together.
List<SettingsSearchEntry> get generalSettingsSearchEntries => [
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
    id: 'persistentSearchBar',
    title: (l) => l.libraryPersistentSearchBar,
    subtitle: (l) => l.libraryPersistentSearchBarSubtitle,
    breadcrumb: (l) => l.general,
    open: (c) =>
        const GeneralSettingsRoute(highlight: 'persistentSearchBar').push(c),
    visible: (_, _) => true,
  ),
];

List<SettingsSearchEntry> get advancedSettingsSearchEntries => [
  SettingsSearchEntry(
    id: 'clearCache',
    title: (l) => l.clearCache,
    breadcrumb: (l) => l.advanced,
    open: (c) => const AdvancedRoute(highlight: 'clearCache').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'removeCustomCovers',
    title: (l) => l.removeCustomCovers,
    breadcrumb: (l) => l.advanced,
    open: (c) => const AdvancedRoute(highlight: 'removeCustomCovers').push(c),
    visible: (_, _) => true,
  ),
];

List<SettingsSearchEntry> get appearanceSettingsSearchEntries => [
  SettingsSearchEntry(
    id: 'appLanguage',
    title: (l) => l.appLanguage,
    breadcrumb: (l) => '${l.appearance} › ${l.display}',
    open: (c) =>
        const AppearanceSettingsRoute(highlight: 'appLanguage').push(c),
    visible: (_, _) => true,
  ),
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
    id: 'mangaThumbnailBackdrop',
    title: (l) => l.mangaThumbnailBackdrop,
    breadcrumb: (l) => '${l.appearance} › ${l.seriesPage}',
    open: (c) => const AppearanceSettingsRoute(
      highlight: 'mangaThumbnailBackdrop',
    ).push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'showRecommendations',
    title: (l) => l.showRecommendations,
    subtitle: (l) => l.showRecommendationsSubtitle,
    breadcrumb: (l) => '${l.appearance} › ${l.seriesPage}',
    open: (c) =>
        const AppearanceSettingsRoute(highlight: 'showRecommendations').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'recommendsInOverflow',
    title: (l) => l.recommendsInOverflow,
    subtitle: (l) => l.recommendsInOverflowSubtitle,
    breadcrumb: (l) => '${l.appearance} › ${l.seriesPage}',
    open: (c) => const AppearanceSettingsRoute(
      highlight: 'recommendsInOverflow',
    ).push(c),
    visible: (ref, _) => ref.watch(showRecommendationsProvider).ifNull(true),
  ),
];

List<SettingsSearchEntry> get librarySettingsSearchEntries => [
  SettingsSearchEntry(
    id: 'removeMangaFromCategories',
    title: (l) => l.removeMangaFromCategories,
    breadcrumb: (l) => '${l.library} › ${l.categories}',
    open: (c) => const LibrarySettingsRoute(
      highlight: 'removeMangaFromCategories',
    ).push(c),
    visible: (ref, _) => _serverReachable(ref),
  ),
  SettingsSearchEntry(
    id: 'ignoreFilters',
    title: (l) => l.ignoreFilters,
    breadcrumb: (l) => '${l.library} › ${l.settingsSectionBehavior}',
    open: (c) => const LibrarySettingsRoute(highlight: 'ignoreFilters').push(c),
    visible: (ref, _) => _serverReachable(ref),
  ),
  SettingsSearchEntry(
    id: 'fuzzySearch',
    title: (l) => l.fuzzySearch,
    breadcrumb: (l) => '${l.library} › ${l.settingsSectionBehavior}',
    open: (c) => const LibrarySettingsRoute(highlight: 'fuzzySearch').push(c),
    visible: (ref, _) => _serverReachable(ref),
  ),
  SettingsSearchEntry(
    id: 'cleanupDatabase',
    title: (l) => l.cleanupDatabase,
    breadcrumb: (l) => '${l.library} › ${l.advanced}',
    open: (c) =>
        const LibrarySettingsRoute(highlight: 'cleanupDatabase').push(c),
    visible: (ref, _) => _serverReachable(ref),
  ),

  SettingsSearchEntry(
    id: 'categories',
    title: (l) => l.categories,
    breadcrumb: (l) => '${l.library} › ${l.categories}',
    open: (c) => const LibrarySettingsRoute(highlight: 'categories').push(c),
    visible: (ref, _) => _serverReachable(ref),
  ),
  SettingsSearchEntry(
    id: 'defaultCategory',
    title: (l) => l.defaultCategoryOnAdd,
    breadcrumb: (l) => '${l.library} › ${l.categories}',
    open: (c) =>
        const LibrarySettingsRoute(highlight: 'defaultCategory').push(c),
    visible: (ref, _) => _serverReachable(ref),
  ),
  SettingsSearchEntry(
    id: 'refreshChaptersFromSource',
    title: (l) => l.refreshChaptersFromSource,
    subtitle: (l) => l.refreshChaptersFromSourceSubtitle,
    breadcrumb: (l) => '${l.library} › ${l.settingsSectionBehavior}',
    open: (c) => const LibrarySettingsRoute(
      highlight: 'refreshChaptersFromSource',
    ).push(c),
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
    breadcrumb: (l) => '${l.library} › ${l.advanced}',
    open: (c) =>
        const LibrarySettingsRoute(highlight: 'duplicatedEntries').push(c),
    visible: (ref, _) => _serverReachable(ref),
  ),
  SettingsSearchEntry(
    id: 'chapterSwipeToLeft',
    title: (l) => l.chapterSwipeToLeft,
    breadcrumb: (l) => '${l.library} › ${l.settingsSectionBehavior}',
    open: (c) =>
        const LibrarySettingsRoute(highlight: 'chapterSwipeToLeft').push(c),
    visible: (ref, _) => _serverReachable(ref),
  ),
  SettingsSearchEntry(
    id: 'chapterSwipeToRight',
    title: (l) => l.chapterSwipeToRight,
    breadcrumb: (l) => '${l.library} › ${l.settingsSectionBehavior}',
    open: (c) =>
        const LibrarySettingsRoute(highlight: 'chapterSwipeToRight').push(c),
    visible: (ref, _) => _serverReachable(ref),
  ),
];

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
    breadcrumb: (l) => '${l.reader} › ${l.readerGroupNavigation}',
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

List<SettingsSearchEntry> get browseSettingsSearchEntries => [
  SettingsSearchEntry(
    id: 'hideLibraryEntries',
    title: (l) => l.hideLibraryEntries,
    breadcrumb: (l) => '${l.browse} › ${l.sources}',
    open: (c) =>
        const BrowseSettingsRoute(highlight: 'hideLibraryEntries').push(c),
    visible: (ref, _) => _serverReachable(ref),
  ),

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
    visible: (_, _) => isAndroidNative,
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

List<SettingsSearchEntry> get backupSettingsSearchEntries => [
  SettingsSearchEntry(
    id: 'includeUserSettings',
    title: (l) => l.includeUserSettings,
    breadcrumb: (l) => '${l.backup} › ${l.backupData}',
    open: openBackupUserSettings,
    visible: (ref, _) =>
        _serverReachable(ref) &&
        _canManageSettings(ref) &&
        ref.watch(autoBackupFlagsProvider).value != null &&
        ref.watch(backupUserSettingsProvider).value != null,
  ),

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

List<SettingsSearchEntry> get downloadsSettingsSearchEntries => [
  SettingsSearchEntry(
    id: 'autoDownloadWhileReading',
    title: (l) => l.autoDownloadWhileReading,
    breadcrumb: (l) => '${l.downloads} › ${l.downloadAhead}',
    open: (c) => const DownloadsSettingsRoute(
      highlight: 'autoDownloadWhileReading',
      tab: 0,
    ).push(c),
    visible: (ref, _) => _serverReachable(ref),
    tabIndex: 0,
  ),
  SettingsSearchEntry(
    id: 'downloadAheadLimit',
    title: (l) => l.downloadAheadLimit,
    breadcrumb: (l) => '${l.downloads} › ${l.downloadAhead}',
    open: (c) => const DownloadsSettingsRoute(
      highlight: 'downloadAheadLimit',
      tab: 0,
    ).push(c),
    visible: (ref, _) => _serverReachable(ref),
    tabIndex: 0,
  ),

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
    breadcrumb: (l) =>
        '${l.downloads} › ${l.downloadsOnDeviceTab} › ${l.offlineBackgroundSection}',
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
    breadcrumb: (l) =>
        '${l.downloads} › ${l.downloadsOnDeviceTab} › ${l.offlineBackgroundSection}',
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
    breadcrumb: (l) =>
        '${l.downloads} › ${l.downloadsOnDeviceTab} › ${l.offlineBackgroundSection}',
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
    breadcrumb: (l) =>
        '${l.downloads} › ${l.downloadsOnDeviceTab} › ${l.offlineStorageSection}',
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
    breadcrumb: (l) =>
        '${l.downloads} › ${l.downloadsOnDeviceTab} › ${l.offlineStorageSection}',
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
    breadcrumb: (l) =>
        '${l.downloads} › ${l.downloadsOnDeviceTab} › ${l.offlineStorageSection}',
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
    breadcrumb: (l) =>
        '${l.downloads} › ${l.downloadsOnDeviceTab} › ${l.offlineStorageSection}',
    open: (c) => const DownloadsSettingsRoute(
      highlight: 'offlineKeepDays',
      tab: 1,
    ).push(c),
    visible: (ref, _) => ref.watch(offlineEnabledProvider),
    tabIndex: 1,
  ),
];

bool _serverReachable(WidgetRef ref) =>
    ref.watch(settingsProvider).value != null;

bool _canManageSettings(WidgetRef ref) => ref
    .watch(settledAccountAccessProvider)
    .allows(Enum$UserPermission.MANAGE_SETTINGS);

bool _imagesRowVisible(WidgetRef ref) {
  final access = ref.watch(settledAccountAccessProvider);
  return access.capability != AccountCapability.supported ||
      access.allows(Enum$UserPermission.MANAGE_SETTINGS);
}

bool _webInterfaceVisible(WidgetRef ref) =>
    _serverReachable(ref) &&
    ref
        .watch(settledAccountAccessProvider)
        .allows(Enum$UserPermission.MANAGE_SETTINGS) &&
    ref.watch(webInterfaceSettingsProvider).value != null;

List<SettingsSearchEntry> get serverNetworkSettingsSearchEntries => [
  SettingsSearchEntry(
    id: 'serverIpAddress',
    title: (l) => l.ip,
    breadcrumb: (l) => '${l.server} › ${l.network} › ${l.serverBindings}',
    open: (c) => const ServerNetworkRoute(highlight: 'serverIpAddress').push(c),
    visible: (ref, _) => _serverReachable(ref) && _canManageSettings(ref),
  ),
  SettingsSearchEntry(
    id: 'serverPort',
    title: (l) => l.serverPort,
    breadcrumb: (l) => '${l.server} › ${l.network} › ${l.serverBindings}',
    open: (c) => const ServerNetworkRoute(highlight: 'serverPort').push(c),
    visible: (ref, _) => _serverReachable(ref) && _canManageSettings(ref),
  ),
  SettingsSearchEntry(
    id: 'enableSocksProxy',
    title: (l) => l.enableSocksProxy,
    breadcrumb: (l) => '${l.server} › ${l.network} › ${l.socksProxy}',
    open: (c) =>
        const ServerNetworkRoute(highlight: 'enableSocksProxy').push(c),
    visible: (ref, _) => _serverReachable(ref) && _canManageSettings(ref),
  ),
  SettingsSearchEntry(
    id: 'socksVersion',
    title: (l) => l.socksVersion,
    breadcrumb: (l) => '${l.server} › ${l.network} › ${l.socksProxy}',
    open: (c) => const ServerNetworkRoute(highlight: 'socksVersion').push(c),
    visible: (ref, _) =>
        _canManageSettings(ref) &&
        (ref.watch(settingsProvider).value?.socksProxyEnabled ?? false),
  ),
  SettingsSearchEntry(
    id: 'socksHost',
    title: (l) => l.socksHost,
    breadcrumb: (l) => '${l.server} › ${l.network} › ${l.socksProxy}',
    open: (c) => const ServerNetworkRoute(highlight: 'socksHost').push(c),
    visible: (ref, _) =>
        _canManageSettings(ref) &&
        (ref.watch(settingsProvider).value?.socksProxyEnabled ?? false),
  ),
  SettingsSearchEntry(
    id: 'socksPort',
    title: (l) => l.socksPort,
    breadcrumb: (l) => '${l.server} › ${l.network} › ${l.socksProxy}',
    open: (c) => const ServerNetworkRoute(highlight: 'socksPort').push(c),
    visible: (ref, _) =>
        _canManageSettings(ref) &&
        (ref.watch(settingsProvider).value?.socksProxyEnabled ?? false),
  ),
  SettingsSearchEntry(
    id: 'socksUserName',
    title: (l) => l.socksUserName,
    breadcrumb: (l) => '${l.server} › ${l.network} › ${l.socksProxy}',
    open: (c) => const ServerNetworkRoute(highlight: 'socksUserName').push(c),
    visible: (ref, _) =>
        _canManageSettings(ref) &&
        (ref.watch(settingsProvider).value?.socksProxyEnabled ?? false),
  ),
  SettingsSearchEntry(
    id: 'socksPassword',
    title: (l) => l.socksPassword,
    breadcrumb: (l) => '${l.server} › ${l.network} › ${l.socksProxy}',
    open: (c) => const ServerNetworkRoute(highlight: 'socksPassword').push(c),
    visible: (ref, _) =>
        _canManageSettings(ref) &&
        (ref.watch(settingsProvider).value?.socksProxyEnabled ?? false),
  ),
  SettingsSearchEntry(
    id: 'flareSolverr',
    title: (l) => l.flareSolverr,
    breadcrumb: (l) => '${l.server} › ${l.network} › ${l.cloudflareBypass}',
    open: (c) => const ServerNetworkRoute(highlight: 'flareSolverr').push(c),
    visible: (ref, _) => _serverReachable(ref) && _canManageSettings(ref),
  ),
  SettingsSearchEntry(
    id: 'flareSolverrServerUrl',
    title: (l) => l.flareSolverrServerUrl,
    breadcrumb: (l) => '${l.server} › ${l.network} › ${l.cloudflareBypass}',
    open: (c) =>
        const ServerNetworkRoute(highlight: 'flareSolverrServerUrl').push(c),
    visible: (ref, _) =>
        _canManageSettings(ref) &&
        (ref.watch(settingsProvider).value?.flareSolverrEnabled ?? false),
  ),
  SettingsSearchEntry(
    id: 'flareSolverrRequestTimeout',
    title: (l) => l.flareSolverrRequestTimeout,
    breadcrumb: (l) => '${l.server} › ${l.network} › ${l.cloudflareBypass}',
    open: (c) => const ServerNetworkRoute(
      highlight: 'flareSolverrRequestTimeout',
    ).push(c),
    visible: (ref, _) =>
        _canManageSettings(ref) &&
        (ref.watch(settingsProvider).value?.flareSolverrEnabled ?? false),
  ),
  SettingsSearchEntry(
    id: 'flareSolverrSessionName',
    title: (l) => l.flareSolverrSessionName,
    breadcrumb: (l) => '${l.server} › ${l.network} › ${l.cloudflareBypass}',
    open: (c) =>
        const ServerNetworkRoute(highlight: 'flareSolverrSessionName').push(c),
    visible: (ref, _) =>
        _canManageSettings(ref) &&
        (ref.watch(settingsProvider).value?.flareSolverrEnabled ?? false),
  ),
  SettingsSearchEntry(
    id: 'flareSolverrSessionTTL',
    title: (l) => l.flareSolverrSessionTTL,
    breadcrumb: (l) => '${l.server} › ${l.network} › ${l.cloudflareBypass}',
    open: (c) =>
        const ServerNetworkRoute(highlight: 'flareSolverrSessionTTL').push(c),
    visible: (ref, _) =>
        _canManageSettings(ref) &&
        (ref.watch(settingsProvider).value?.flareSolverrEnabled ?? false),
  ),
  SettingsSearchEntry(
    id: 'flareSolverrResponseFallback',
    title: (l) => l.responseFallback,
    subtitle: (l) => l.responseFallbackDescription,
    breadcrumb: (l) => '${l.server} › ${l.network} › ${l.cloudflareBypass}',
    open: (c) => const ServerNetworkRoute(
      highlight: 'flareSolverrResponseFallback',
    ).push(c),
    visible: (ref, _) =>
        _canManageSettings(ref) &&
        (ref.watch(settingsProvider).value?.flareSolverrEnabled ?? false) &&
        ref.watch(flareSolverrFallbackProvider).value != null,
  ),
  SettingsSearchEntry(
    id: 'webview',
    title: (l) => l.kcefWebView,
    subtitle: (l) => l.kcefWebViewDescription,
    breadcrumb: (l) => '${l.server} › ${l.network} › ${l.kcefWebView}',
    open: (c) => const ServerNetworkRoute(highlight: 'webview').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) &&
        _canManageSettings(ref) &&
        ref.watch(webViewSettingsProvider).value != null,
  ),
  SettingsSearchEntry(
    id: 'clearWebViewCache',
    title: (l) => l.clearCookiesAndCache,
    breadcrumb: (l) => '${l.server} › ${l.network} › ${l.kcefWebView}',
    open: (c) =>
        const ServerNetworkRoute(highlight: 'clearWebViewCache').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) &&
        _canManageSettings(ref) &&
        (ref.watch(clearCookiesAndCacheSupportProvider).value ?? false),
  ),
];

List<SettingsSearchEntry> get serverWebInterfaceSettingsSearchEntries => [
  SettingsSearchEntry(
    id: 'webInterfaceFlavor',
    title: (l) => l.webInterfaceInterface,
    breadcrumb: (l) => '${l.server} › ${l.webInterface}',
    open: (c) =>
        const ServerWebInterfaceRoute(highlight: 'webInterfaceFlavor').push(c),
    visible: (ref, _) => _webInterfaceVisible(ref),
  ),
  SettingsSearchEntry(
    id: 'initialOpenInBrowserEnabled',
    title: (l) => l.initialOpenInBrowserEnabled,
    breadcrumb: (l) => '${l.server} › ${l.webInterface}',
    open: (c) => const ServerWebInterfaceRoute(
      highlight: 'initialOpenInBrowserEnabled',
    ).push(c),
    visible: (ref, _) => _webInterfaceVisible(ref),
  ),
  SettingsSearchEntry(
    id: 'webInterfaceInterface',
    title: (l) => l.webInterfaceOpenWith,
    breadcrumb: (l) => '${l.server} › ${l.webInterface}',
    open: (c) => const ServerWebInterfaceRoute(
      highlight: 'webInterfaceInterface',
    ).push(c),
    visible: (ref, _) => _webInterfaceVisible(ref),
  ),
  SettingsSearchEntry(
    id: 'electronPath',
    title: (l) => l.electronPath,
    breadcrumb: (l) => '${l.server} › ${l.webInterface}',
    open: (c) =>
        const ServerWebInterfaceRoute(highlight: 'electronPath').push(c),
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
        const ServerWebInterfaceRoute(highlight: 'webInterfaceChannel').push(c),
    visible: (ref, _) => _webInterfaceVisible(ref),
  ),
  SettingsSearchEntry(
    id: 'webInterfaceAutomaticUpdates',
    title: (l) => l.webInterfaceAutomaticUpdates,
    breadcrumb: (l) => '${l.server} › ${l.webInterface}',
    open: (c) => const ServerWebInterfaceRoute(
      highlight: 'webInterfaceAutomaticUpdates',
    ).push(c),
    visible: (ref, _) => _webInterfaceVisible(ref),
  ),
  SettingsSearchEntry(
    id: 'webInterfaceCheckUpdate',
    title: (l) => l.webInterfaceCheckUpdate,
    breadcrumb: (l) => '${l.server} › ${l.webInterface}',
    open: (c) => const ServerWebInterfaceRoute(
      highlight: 'webInterfaceCheckUpdate',
    ).push(c),
    visible: (ref, _) =>
        _serverReachable(ref) &&
        _canManageSettings(ref) &&
        ref.watch(settledAccountAccessProvider).capability !=
            AccountCapability.unknown &&
        ref.watch(webInterfaceSettingsProvider).value?.webUIFlavor !=
            Enum$WebUIFlavor.CUSTOM,
  ),
];

List<SettingsSearchEntry> get serverOpdsSettingsSearchEntries => [
  SettingsSearchEntry(
    id: 'opdsBinaryFileSize',
    title: (l) => l.opdsBinaryFileSize,
    subtitle: (l) => l.opdsBinaryFileSizeDescription,
    breadcrumb: (l) => '${l.server} › ${l.opds}',
    open: (c) => const ServerOpdsRoute(highlight: 'opdsBinaryFileSize').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) && ref.watch(opdsSettingsProvider).value != null,
  ),
  SettingsSearchEntry(
    id: 'opdsItemsPerPage',
    title: (l) => l.opdsItemsPerPage,
    subtitle: (l) => l.opdsItemsPerPageDescription,
    breadcrumb: (l) => '${l.server} › ${l.opds}',
    open: (c) => const ServerOpdsRoute(highlight: 'opdsItemsPerPage').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) && ref.watch(opdsSettingsProvider).value != null,
  ),
  SettingsSearchEntry(
    id: 'opdsEnablePageReadProgress',
    title: (l) => l.opdsEnablePageReadProgress,
    subtitle: (l) => l.opdsEnablePageReadProgressDescription,
    breadcrumb: (l) => '${l.server} › ${l.opds}',
    open: (c) =>
        const ServerOpdsRoute(highlight: 'opdsEnablePageReadProgress').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) && ref.watch(opdsSettingsProvider).value != null,
  ),
  SettingsSearchEntry(
    id: 'opdsMarkAsReadOnDownload',
    title: (l) => l.opdsMarkAsReadOnDownload,
    subtitle: (l) => l.opdsMarkAsReadOnDownloadDescription,
    breadcrumb: (l) => '${l.server} › ${l.opds}',
    open: (c) =>
        const ServerOpdsRoute(highlight: 'opdsMarkAsReadOnDownload').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) && ref.watch(opdsSettingsProvider).value != null,
  ),
  SettingsSearchEntry(
    id: 'opdsShowOnlyUnreadChapters',
    title: (l) => l.opdsShowOnlyUnreadChapters,
    subtitle: (l) => l.opdsShowOnlyUnreadChaptersDescription,
    breadcrumb: (l) => '${l.server} › ${l.opds}',
    open: (c) =>
        const ServerOpdsRoute(highlight: 'opdsShowOnlyUnreadChapters').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) && ref.watch(opdsSettingsProvider).value != null,
  ),
  SettingsSearchEntry(
    id: 'opdsShowOnlyDownloadedChapters',
    title: (l) => l.opdsShowOnlyDownloadedChapters,
    subtitle: (l) => l.opdsShowOnlyDownloadedChaptersDescription,
    breadcrumb: (l) => '${l.server} › ${l.opds}',
    open: (c) => const ServerOpdsRoute(
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
    open: (c) =>
        const ServerOpdsRoute(highlight: 'opdsSkipChapterMetadataFeed').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) && ref.watch(opdsSettingsProvider).value != null,
  ),
  SettingsSearchEntry(
    id: 'opdsChapterSortOrder',
    title: (l) => l.opdsChapterSortOrder,
    breadcrumb: (l) => '${l.server} › ${l.opds}',
    open: (c) =>
        const ServerOpdsRoute(highlight: 'opdsChapterSortOrder').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) && ref.watch(opdsSettingsProvider).value != null,
  ),
  SettingsSearchEntry(
    id: 'opdsCbzMimetype',
    title: (l) => l.opdsCbzMimeType,
    breadcrumb: (l) => '${l.server} › ${l.opds}',
    open: (c) => const ServerOpdsRoute(highlight: 'opdsCbzMimetype').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) && ref.watch(opdsSettingsProvider).value != null,
  ),
];

List<SettingsSearchEntry> get serverImagesSettingsSearchEntries => [
  SettingsSearchEntry(
    id: 'imagesClearCache',
    title: (l) => l.imageProcessingClearCache,
    breadcrumb: (l) => '${l.server} › ${l.images}',
    open: (c) => const ServerImagesRoute(highlight: 'imagesClearCache').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) &&
        _imagesRowVisible(ref) &&
        (ref.watch(clearCachedImagesSupportProvider).value ?? false),
  ),
  SettingsSearchEntry(
    id: 'imageDownloadProcessing',
    title: (l) => l.imageDownloadProcessing,
    breadcrumb: (l) => '${l.server} › ${l.images}',
    open: (c) =>
        const ServerImagesRoute(highlight: 'imageDownloadProcessing').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) &&
        _imagesRowVisible(ref) &&
        ref.watch(imagesDownloadSettingsProvider).value != null,
  ),
  SettingsSearchEntry(
    id: 'imageServeProcessing',
    title: (l) => l.imageServeProcessing,
    breadcrumb: (l) => '${l.server} › ${l.images}',
    open: (c) =>
        const ServerImagesRoute(highlight: 'imageServeProcessing').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) &&
        ref.watch(serveConversionsProvider).value != null,
  ),
];

List<SettingsSearchEntry> get serverSignInSettingsSearchEntries => [
  SettingsSearchEntry(
    id: 'serverAuthMode',
    title: (l) => l.serverAuthMode,
    breadcrumb: (l) => '${l.server} › ${l.serverSignIn}',
    open: (c) => const ServerSignInRoute(highlight: 'serverAuthMode').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) &&
        _canManageSettings(ref) &&
        ref.watch(signInSettingsProvider).value != null &&
        ref.watch(signInAccountsCapabilityProvider).value != null &&
        ref.watch(signInAccountsCapabilityProvider).value !=
            AccountCapability.unknown,
  ),
  SettingsSearchEntry(
    id: 'serverAuthUsername',
    title: (l) => l.serverAuthUsername,
    breadcrumb: (l) => '${l.server} › ${l.serverSignIn}',
    open: (c) =>
        const ServerSignInRoute(highlight: 'serverAuthUsername').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) &&
        _canManageSettings(ref) &&
        ref.watch(signInSettingsProvider).value != null &&
        ref.watch(signInAccountsCapabilityProvider).value != null &&
        ref.watch(signInAccountsCapabilityProvider).value !=
            AccountCapability.unknown &&
        signInAdmin(
          accounts:
              ref.watch(signInAccountsCapabilityProvider).value ==
              AccountCapability.supported,
          mode:
              ref.watch(signInSettingsProvider).value!.authMode ==
                  Enum$AuthMode.UI_LOGIN
              ? AuthType.uiLogin
              : AuthType.none,
          userId: ref.watch(currentAccountProvider)?.id,
        ),
  ),
  SettingsSearchEntry(
    id: 'serverAuthPassword',
    title: (l) => l.serverAuthPassword,
    breadcrumb: (l) => '${l.server} › ${l.serverSignIn}',
    open: (c) =>
        const ServerSignInRoute(highlight: 'serverAuthPassword').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) &&
        _canManageSettings(ref) &&
        ref.watch(signInSettingsProvider).value != null &&
        ref.watch(signInAccountsCapabilityProvider).value != null &&
        ref.watch(signInAccountsCapabilityProvider).value !=
            AccountCapability.unknown &&
        signInAdmin(
          accounts:
              ref.watch(signInAccountsCapabilityProvider).value ==
              AccountCapability.supported,
          mode:
              ref.watch(signInSettingsProvider).value!.authMode ==
                  Enum$AuthMode.UI_LOGIN
              ? AuthType.uiLogin
              : AuthType.none,
          userId: ref.watch(currentAccountProvider)?.id,
        ),
  ),
  SettingsSearchEntry(
    id: 'serverJwtAudience',
    title: (l) => l.serverJwtAudience,
    breadcrumb: (l) => '${l.server} › ${l.serverSignIn}',
    open: (c) =>
        const ServerSignInRoute(highlight: 'serverJwtAudience').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) &&
        _canManageSettings(ref) &&
        ref.watch(signInSettingsProvider).value != null &&
        ref.watch(signInAccountsCapabilityProvider).value != null &&
        ref.watch(signInAccountsCapabilityProvider).value !=
            AccountCapability.unknown &&
        ref.watch(signInSettingsProvider).value!.authMode ==
            Enum$AuthMode.UI_LOGIN,
  ),
  SettingsSearchEntry(
    id: 'serverAccessExpiry',
    title: (l) => l.serverAccessExpiry,
    breadcrumb: (l) => '${l.server} › ${l.serverSignIn}',
    open: (c) =>
        const ServerSignInRoute(highlight: 'serverAccessExpiry').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) &&
        _canManageSettings(ref) &&
        ref.watch(signInSettingsProvider).value != null &&
        ref.watch(signInAccountsCapabilityProvider).value != null &&
        ref.watch(signInAccountsCapabilityProvider).value !=
            AccountCapability.unknown &&
        ref.watch(signInSettingsProvider).value!.authMode ==
            Enum$AuthMode.UI_LOGIN,
  ),
  SettingsSearchEntry(
    id: 'serverRefreshExpiry',
    title: (l) => l.serverRefreshExpiry,
    breadcrumb: (l) => '${l.server} › ${l.serverSignIn}',
    open: (c) =>
        const ServerSignInRoute(highlight: 'serverRefreshExpiry').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) &&
        _canManageSettings(ref) &&
        ref.watch(signInSettingsProvider).value != null &&
        ref.watch(signInAccountsCapabilityProvider).value != null &&
        ref.watch(signInAccountsCapabilityProvider).value !=
            AccountCapability.unknown &&
        ref.watch(signInSettingsProvider).value!.authMode ==
            Enum$AuthMode.UI_LOGIN,
  ),
];

List<SettingsSearchEntry> get serverDatabaseSettingsSearchEntries => [
  SettingsSearchEntry(
    id: 'databaseSchema',
    title: (l) => l.databaseSchema,
    breadcrumb: (l) => '${l.server} › ${l.database}',
    open: (c) => const ServerDatabaseRoute(highlight: 'databaseSchema').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) &&
        _canManageSettings(ref) &&
        ref.watch(databaseSettingsProvider).value != null &&
        ref.watch(previewDatabaseSettingsProvider).value != null,
  ),
  SettingsSearchEntry(
    id: 'hikariMaxPoolSize',
    title: (l) => l.hikariMaxPoolSize,
    breadcrumb: (l) => '${l.server} › ${l.database}',
    open: (c) =>
        const ServerDatabaseRoute(highlight: 'hikariMaxPoolSize').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) &&
        _canManageSettings(ref) &&
        ref.watch(databaseSettingsProvider).value != null &&
        ref.watch(previewDatabaseSettingsProvider).value != null,
  ),

  SettingsSearchEntry(
    id: 'databaseType',
    title: (l) => l.databaseType,
    breadcrumb: (l) => '${l.server} › ${l.database}',
    open: (c) => const ServerDatabaseRoute(highlight: 'databaseType').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) &&
        _canManageSettings(ref) &&
        ref.watch(databaseSettingsProvider).value != null,
  ),
  SettingsSearchEntry(
    id: 'databaseUrl',
    title: (l) => l.databaseUrl,
    breadcrumb: (l) => '${l.server} › ${l.database}',
    open: (c) => const ServerDatabaseRoute(highlight: 'databaseUrl').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) &&
        _canManageSettings(ref) &&
        ref.watch(databaseSettingsProvider).value != null,
  ),
  SettingsSearchEntry(
    id: 'databaseUsername',
    title: (l) => l.databaseUsername,
    breadcrumb: (l) => '${l.server} › ${l.database}',
    open: (c) =>
        const ServerDatabaseRoute(highlight: 'databaseUsername').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) &&
        _canManageSettings(ref) &&
        ref.watch(databaseSettingsProvider).value != null,
  ),
  SettingsSearchEntry(
    id: 'databasePassword',
    title: (l) => l.databasePassword,
    breadcrumb: (l) => '${l.server} › ${l.database}',
    open: (c) =>
        const ServerDatabaseRoute(highlight: 'databasePassword').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) &&
        _canManageSettings(ref) &&
        ref.watch(databaseSettingsProvider).value != null,
  ),
  SettingsSearchEntry(
    id: 'hikariConnectionPool',
    title: (l) => l.hikariConnectionPool,
    subtitle: (l) => l.hikariConnectionPoolDescription,
    breadcrumb: (l) => '${l.server} › ${l.database}',
    open: (c) =>
        const ServerDatabaseRoute(highlight: 'hikariConnectionPool').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) &&
        _canManageSettings(ref) &&
        ref.watch(databaseSettingsProvider).value != null,
  ),
];

List<SettingsSearchEntry> get serverLogsSettingsSearchEntries => [
  SettingsSearchEntry(
    id: 'debugLogs',
    title: (l) => l.debugLogs,
    breadcrumb: (l) => '${l.server} › ${l.logs}',
    open: (c) => const ServerLogsRoute(highlight: 'debugLogs').push(c),
    visible: (ref, _) => _serverReachable(ref) && _canManageSettings(ref),
  ),
  SettingsSearchEntry(
    id: 'systemTrayIcon',
    title: (l) => l.systemTrayIcon,
    breadcrumb: (l) => '${l.server} › ${l.logs}',
    open: (c) => const ServerLogsRoute(highlight: 'systemTrayIcon').push(c),
    visible: (ref, _) => _serverReachable(ref) && _canManageSettings(ref),
  ),
  SettingsSearchEntry(
    id: 'logFileCleanup',
    title: (l) => l.logFileCleanup,
    breadcrumb: (l) => '${l.server} › ${l.logs}',
    open: (c) => const ServerLogsRoute(highlight: 'logFileCleanup').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) &&
        _canManageSettings(ref) &&
        ref.watch(miscLogsSettingsProvider).value != null,
  ),
  SettingsSearchEntry(
    id: 'maxLogFileSize',
    title: (l) => l.maxLogFileSize,
    subtitle: (l) => l.logSizeExamples,
    breadcrumb: (l) => '${l.server} › ${l.logs}',
    open: (c) => const ServerLogsRoute(highlight: 'maxLogFileSize').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) &&
        _canManageSettings(ref) &&
        ref.watch(miscLogsSettingsProvider).value != null,
  ),
  SettingsSearchEntry(
    id: 'maxLogFolderSize',
    title: (l) => l.maxLogFolderSize,
    subtitle: (l) => l.logSizeExamples,
    breadcrumb: (l) => '${l.server} › ${l.logs}',
    open: (c) => const ServerLogsRoute(highlight: 'maxLogFolderSize').push(c),
    visible: (ref, _) =>
        _serverReachable(ref) &&
        _canManageSettings(ref) &&
        ref.watch(miscLogsSettingsProvider).value != null,
  ),
];

List<SettingsSearchEntry> get connectionSettingsSearchEntries => [
  SettingsSearchEntry(
    id: 'serverUrl',
    title: (l) => l.serverUrl,
    breadcrumb: (l) => '${l.connection} › ${l.server}',
    open: (c) => const ConnectionRoute(highlight: 'serverUrl').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'serverLanUrl',
    title: (l) => l.serverLanUrl,
    breadcrumb: (l) => '${l.connection} › ${l.server}',
    open: (c) => const ConnectionRoute(highlight: 'serverLanUrl').push(c),
    visible: (ref, _) => ref.watch(serverLanUrlProvider) != null,
  ),
  SettingsSearchEntry(
    id: 'authentication',
    title: (l) => l.authType,
    breadcrumb: (l) => '${l.connection} › ${l.accountTitle}',
    open: (c) => const ConnectionRoute(highlight: 'authentication').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'customHeaders',
    title: (l) => l.customHeaders,
    breadcrumb: (l) => '${l.connection} › ${l.customHeaders}',
    open: (c) => const ConnectionRoute(highlight: 'customHeaders').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'openInWeb',
    title: (l) => l.webUI,
    breadcrumb: (l) => '${l.connection} › ${l.server}',
    open: (c) => const ConnectionRoute(highlight: 'openInWeb').push(c),
    visible: (_, _) => !kIsWeb,
  ),
  SettingsSearchEntry(
    id: 'serverRequestTimeout',
    title: (l) => l.serverRequestTimeout,
    breadcrumb: (l) => '${l.connection} › ${l.timeouts}',
    open: (c) =>
        const ConnectionRoute(highlight: 'serverRequestTimeout').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'autoRefreshOnTimeout',
    title: (l) => l.autoRefreshOnTimeout,
    subtitle: (l) => l.autoRefreshOnTimeoutDescription,
    breadcrumb: (l) => '${l.connection} › ${l.timeouts}',
    open: (c) =>
        const ConnectionRoute(highlight: 'autoRefreshOnTimeout').push(c),
    visible: (_, _) => true,
  ),
  SettingsSearchEntry(
    id: 'autoRefreshRetryDelay',
    title: (l) => l.autoRefreshRetryDelay,
    breadcrumb: (l) => '${l.connection} › ${l.timeouts}',
    open: (c) =>
        const ConnectionRoute(highlight: 'autoRefreshRetryDelay').push(c),
    visible: (ref, _) => ref.watch(autoRefreshOnTimeoutProvider).ifNull(),
  ),
];

bool _syncYomiSupported(WidgetRef ref) =>
    ref.watch(syncYomiSettingsProvider).value != null;

bool _koreaderSyncSupported(WidgetRef ref) =>
    ref.watch(koreaderSyncSettingsProvider).value != null &&
    ref.watch(koSyncStatusProvider).value != null;

List<SettingsSearchEntry> get syncSettingsSearchEntries => [
  SettingsSearchEntry(
    id: 'syncYomiEnabled',
    title: (l) => l.syncYomiEnabled,
    breadcrumb: (l) => '${l.sync} › ${l.syncyomi}',
    open: (c) => const SyncRoute(highlight: 'syncYomiEnabled').push(c),
    visible: (ref, _) => _syncYomiSupported(ref),
  ),
  SettingsSearchEntry(
    id: 'syncYomiHost',
    title: (l) => l.syncYomiHost,
    breadcrumb: (l) => '${l.sync} › ${l.syncyomi}',
    open: (c) => const SyncRoute(highlight: 'syncYomiHost').push(c),
    visible: (ref, _) => _syncYomiSupported(ref),
  ),
  SettingsSearchEntry(
    id: 'syncYomiApiKey',
    title: (l) => l.syncYomiApiKey,
    breadcrumb: (l) => '${l.sync} › ${l.syncyomi}',
    open: (c) => const SyncRoute(highlight: 'syncYomiApiKey').push(c),
    visible: (ref, _) => _syncYomiSupported(ref),
  ),
  SettingsSearchEntry(
    id: 'syncYomiSyncInterval',
    title: (l) => l.syncYomiSyncInterval,
    breadcrumb: (l) => '${l.sync} › ${l.syncyomi}',
    open: (c) => const SyncRoute(highlight: 'syncYomiSyncInterval').push(c),
    visible: (ref, _) => _syncYomiSupported(ref),
  ),
  SettingsSearchEntry(
    id: 'syncYomiSyncData',
    title: (l) => l.syncYomiSyncData,
    breadcrumb: (l) => '${l.sync} › ${l.syncyomi}',
    open: (c) => const SyncRoute(highlight: 'syncYomiSyncData').push(c),
    visible: (ref, _) => _syncYomiSupported(ref),
  ),
  SettingsSearchEntry(
    id: 'syncYomiSyncNow',
    title: (l) => l.syncYomiSyncNow,
    breadcrumb: (l) => '${l.sync} › ${l.syncyomi}',
    open: (c) => const SyncRoute(highlight: 'syncYomiSyncNow').push(c),
    visible: (ref, _) {
      final settings = ref.watch(syncYomiSettingsProvider).value;
      return settings != null &&
          settings.enabled &&
          settings.host.isNotBlank &&
          settings.apiKey.isNotBlank;
    },
  ),
  SettingsSearchEntry(
    id: 'koreaderSyncStatus',
    title: (l) => l.koreaderSyncStatus,
    breadcrumb: (l) => '${l.sync} › ${l.koreaderSync}',
    open: (c) => const SyncRoute(highlight: 'koreaderSyncStatus').push(c),
    visible: (ref, _) => _koreaderSyncSupported(ref),
  ),
  SettingsSearchEntry(
    id: 'koreaderSyncStrategyForward',
    title: (l) => l.koreaderSyncStrategyForward,
    breadcrumb: (l) => '${l.sync} › ${l.koreaderSync}',
    open: (c) =>
        const SyncRoute(highlight: 'koreaderSyncStrategyForward').push(c),
    visible: (ref, _) => _koreaderSyncSupported(ref),
  ),
  SettingsSearchEntry(
    id: 'koreaderSyncStrategyBackward',
    title: (l) => l.koreaderSyncStrategyBackward,
    breadcrumb: (l) => '${l.sync} › ${l.koreaderSync}',
    open: (c) =>
        const SyncRoute(highlight: 'koreaderSyncStrategyBackward').push(c),
    visible: (ref, _) => _koreaderSyncSupported(ref),
  ),
  SettingsSearchEntry(
    id: 'koreaderSyncChecksumMethod',
    title: (l) => l.koreaderSyncChecksumMethod,
    breadcrumb: (l) => '${l.sync} › ${l.koreaderSync}',
    open: (c) =>
        const SyncRoute(highlight: 'koreaderSyncChecksumMethod').push(c),
    visible: (ref, _) => _koreaderSyncSupported(ref),
  ),
  SettingsSearchEntry(
    id: 'koreaderSyncPercentageTolerance',
    title: (l) => l.koreaderSyncPercentageTolerance,
    breadcrumb: (l) => '${l.sync} › ${l.koreaderSync}',
    open: (c) =>
        const SyncRoute(highlight: 'koreaderSyncPercentageTolerance').push(c),
    visible: (ref, _) => _koreaderSyncSupported(ref),
  ),
];

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

/// Keeps server providers alive for the open search, even when matching stops at local results.
void pinSettingsSearchProviders(WidgetRef ref) {
  ref.watch(settingsProvider);
  ref.watch(webInterfaceSettingsProvider);
  ref.watch(syncYomiSettingsProvider);
  ref.watch(koreaderSyncSettingsProvider);
  ref.watch(koSyncStatusProvider);
}

List<SettingsSearchEntry> get allSettingsSearchEntries => [
  ...generalSettingsSearchEntries,
  ...advancedSettingsSearchEntries,
  ...appearanceSettingsSearchEntries,
  ...librarySettingsSearchEntries,
  ...readerSettingsSearchEntries,
  ...browseSettingsSearchEntries,
  ...notificationsSettingsSearchEntries,
  ...backupSettingsSearchEntries,
  ...downloadsSettingsSearchEntries,
  ...serverSignInSettingsSearchEntries,
  ...serverNetworkSettingsSearchEntries,
  ...serverWebInterfaceSettingsSearchEntries,
  ...serverOpdsSettingsSearchEntries,
  ...serverImagesSettingsSearchEntries,
  ...serverDatabaseSettingsSearchEntries,
  ...serverLogsSettingsSearchEntries,
  ...connectionSettingsSearchEntries,
  ...syncSettingsSearchEntries,
  ...trackingSettingsSearchEntries,
];
