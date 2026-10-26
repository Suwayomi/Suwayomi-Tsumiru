// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'enum.dart';

enum DBKeys {
  serverUrl('http://127.0.0.1'),
  // External address; serverUrl holds the currently selected endpoint.
  serverExternalUrl(null),
  serverLanUrl(null),
  serverPort(4567),
  serverPortToggle(true),
  onboardingComplete(false),
  sourceLanguageFilter(["all", "lastUsed", "en", "localsourcelang"]),
  // Source ids in descending migration priority.
  migrationTargetSources(<String>[]),
  migrationSourceSort(MigrationSourceSort.alphabetical),
  migrationSourceAscending(true),
  migrationSourceObsoleteOnly(false),
  extensionLanguageFilter(["installed", "update", "en", "all"]),
  sourceLastUsed(null),
  sourceRecentIds(<String>[]),
  // Fresh installs are seeded dark by seedFirstRunPreferences.
  themeMode(ThemeMode.system),
  isTrueBlack(false),
  authType(AuthType.none),
  basicCredentials(null),
  authUsername(null),
  // Blocks reuse of credentials left behind by a refused secure-storage delete.
  authCredentialsInvalidated(false),
  readerMode(ReaderMode.singleHorizontalRTL),
  readerPadding(0.0),
  // Compensates for Flutter Linux's 53 px mouse-wheel step.
  readerMouseScrollSpeed(1.7),
  // Migration source for per-viewer navigation keys; not read directly.
  readerNavigationLayout(ReaderNavigationLayout.defaultNavigation),
  invertTap(false),
  quickSearchToggle(true),
  swipeToggle(true),
  lastPageSwipeEnabled(false),
  scrollAnimation(true),
  showNSFW(true),
  showRecommendations(true),
  recommendsInOverflow(false),
  mangaThumbnailBackdrop(null),
  downloadedBadge(false),
  onDeviceBadge(true),
  unreadBadgeMode(UnreadBadgeMode.count),
  readProgressBar(false),
  languageBadge(false),
  sourceBadge(false),
  libraryGridStyle(LibraryGridStyle.uniform),
  outlineOnCovers(true),
  // Persist LibraryBadge ids; badgeRightSide assigns physical top-right placement.
  badgeOrder(<String>[]),
  badgeRightSide(<String>['onDevice', 'language', 'source']),
  limitTitleLines(true),
  listScale(1.0),
  libraryGroupStyle(LibraryGroupStyle.tabs),
  showContinueReadingButton(false),
  // -1 asks for a category; 0 is uncategorized; positive values are category ids.
  libraryDefaultCategory(-1),
  // Null follows the device locale, falling back to English.
  l10n(null),
  mangaFilterDownloaded(null),
  mangaFilterOffline(null),
  mangaFilterUnread(null),
  mangaFilterCompleted(null),
  mangaFilterStarted(null),
  mangaFilterBookmarked(null),
  chapterFilterDownloaded(null),
  chapterFilterUnread(null),
  chapterFilterBookmarked(null),
  updatesFilterDownloaded(null),
  updatesFilterUnread(null),
  updatesFilterStarted(null),
  updatesFilterBookmarked(null),
  updatesGroupingMode(null),
  updatesDisplayMode(null),
  upcomingView(null),
  upcomingShowPastReleases(true),
  historyFilterUnfinishedSeries(null),
  historyFilterUnread(null),
  historyFilterInLibrary(null),
  mangaSort(MangaSort.lastRead),
  // asc=true, dsc=false.
  mangaSortDirection(false),
  chapterSort(ChapterSort.source),
  chapterSortDirection(false), // asc=true, dsc=false
  chapterDisplay(ChapterDisplay.sourceTitle),
  libraryDisplayMode(DisplayMode.grid),
  sourceDisplayMode(DisplayMode.grid),
  globalSearchSourceFilter(GlobalSearchSourceFilter.pinned),
  gridMangaCoverWidth(192.0),
  readerOverlay(false),
  readerFeedbackToasts(true),
  volumeTap(false),
  volumeTapInvert(false),
  keepScreenOn(true),
  hideEmptyCategory(false),
  showUpdateProgressBanner(true),
  sidebarExpanded(true),
  refreshChaptersFromSource(false),
  pinchToZoom(true),
  readerIgnoreSafeArea(true),
  appTheme(AppTheme.indigoNight),
  customThemeColor(0xFF7C7BFF),
  historyEnabled(true),
  historyRetentionDays(90),
  // Keep synchronized with TimeoutConstants.requestTimeoutDefaultMs.
  serverRequestTimeout(30000), // milliseconds
  autoRefreshOnTimeout(true),
  autoRefreshRetryDelay(1000), // milliseconds
  offlineTimeEvictEnabled(false),
  offlineKeepDays(30),
  offlineStorageCapEnabled(false),
  offlineStorageCapMb(2000),
  // Low concurrency avoids saturating self-hosted servers.
  offlineDownloadConcurrency(2),
  downloadOnlyOverWifi(true),
  onlyMyDownloads(true),
  // Persist explicit device-download pauses across restarts.
  offlineDownloadsPaused(false),
  offlineDownloadsStalled(null),
  offlineCatalogServerId(null),
  // Newest processed chapter fetchedAt, in epoch seconds.
  offlineCatchUpWatermark(0),
  // Persist pending device pulls because the watermark already passed their chapters.
  offlineCatchUpAwaitingPull(null),
  offlineLastServerId(null),
  offlineLastServerAddress(null),
  offlineServerMismatchDismissedList(null),
  notificationsNewChaptersEnabled(false),
  notificationsDownloadsEnabled(true),
  notificationsCheckIntervalHours(6),
  notificationsWifiOnly(true),
  notificationsChargingOnly(false),
  notificationsHideContent(false),
  notificationsCategoriesInclude(null),
  notificationsCategoriesExclude(null),
  notificationsAppUpdatesEnabled(false),
  notificationsExtensionUpdatesEnabled(false),
  // Device-only deletion: 0=off, 1=just read, 2..5=Nth chapter behind.
  localDeleteWhileReading(0),
  localDeleteManuallyMarkedRead(false),
  localDeleteWithBookmark(false),
  // Reconciles missing device copies within the slots-1 recently read protection window.
  localDownloadProtectionWindow(false),
  // Applies only to phones.
  forcePortrait(false),
  dismissedUpdateVersion(''),
  lastSeenServerVersion(''),
  updateProgressAfterReading(true),
  updateProgressManualMarkRead(true),
  // 0 selects automatic columns using gridMangaCoverWidth.
  libraryPortraitColumns(0),
  libraryLandscapeColumns(0),
  // Hides only the tab bar; pages remain swipeable.
  categoryTabs(true),
  // Section headers: true uses one continuous scroll; false uses a page per section.
  sectionHeadersShowAllCategories(false),
  showHiddenCategories(false),
  categoryNumberOfItems(false),
  libraryPersistentSearchBar(false),
  // 0=category, 1=source, 2=status, 3=track status, 4=ungrouped.
  libraryGroupType(0),
  mangaFilterLewd(null),
  // 0 disables the minimum-rating filter.
  mangaFilterMinRating(0),
  filterCategories(false),
  filterCategoriesInclude(<String>[]),
  filterCategoriesExclude(<String>[]),
  filterTags(false),
  filterTagsInclude(<String>[]),
  filterTagsExclude(<String>[]),
  librarySortRandomSeed(0),
  // Description substring matching adds an O(n²) duplicate scan.
  libraryDuplicatesCheckDescription(false),
  forceHorizontalSeekbar(false),
  leftHandedVerticalSeekbar(false),
  doubleTapToZoom(true),
  disableZoomOut(false),
  disableZoomIn(false),
  // Unset per-viewer zoom keys fall back to the legacy global values above.
  pagedDoubleTapToZoom(true),
  pagedPinchToZoom(true),
  pagedDisableZoomOut(false),
  longStripDoubleTapToZoom(true),
  longStripPinchToZoom(true),
  longStripDisableZoomOut(false),
  chapterSwipeToLeft(ChapterSwipeAction.toggleBookmark),
  chapterSwipeToRight(ChapterSwipeAction.toggleRead),
  // Applies tag/source-based webtoon detection only to series in Default mode.
  autoWebtoonMode(true),
  readerOrientation(ReaderOrientation.defaultRotation),
  // Null preserves fallback to the legacy invertTap bool.
  readerTapInvert(null),
  imageScaleType(ImageScaleType.fitScreen),
  zoomStart(ZoomStart.automatic),
  pageLayout(PageLayout.automatic),
  centerMarginType(CenterMarginType.none),
  landscapeZoom(true),
  navigateToPan(true),
  invertDoublePages(false),
  cropBorders(false),
  smallerTapZones(false),
  // Seeded from the global navigation keys on upgrade.
  pagedNavigationLayout(ReaderNavigationLayout.defaultNavigation),
  longStripNavigationLayout(ReaderNavigationLayout.defaultNavigation),
  pagedTapInvert(TapInvert.none),
  longStripTapInvert(TapInvert.none),
  showTapZonesOverlay(false),
  // One-time tap-zone preview; clears itself after display.
  tapZonesOverlayUnseen(true),
  animatePageTransitions(true),
  dualPageSplitPaged(false),
  dualPageInvertPaged(false),
  rotateWidePages(false),
  rotateWideInvert(false),
  trueDualPageSpread(false),
  webtoonScaleType(WebtoonScaleType.fitScreen),
  longStripWidthLimitUsePixels(false),
  longStripWidthLimitPercent(100),
  longStripWidthLimitPx(800),
  cropBordersWebtoon(false),
  cropBordersGaps(false),
  smoothAutoScroll(true),
  readerScrollAmount(ReaderScrollAmount.large),
  autoScrollIntervalSeconds(3),
  autoAdvanceIntervalSeconds(5),
  dualPageSplitWebtoon(false),
  dualPageInvertWebtoon(false),
  readerBackgroundColor(ReaderBackgroundColor.black),
  showPageNumber(true),
  landscapeVerticalSeekbar(false),
  readerFullscreen(true),
  drawUnderCutout(true),
  readWithLongTap(true),
  alwaysShowChapterTransition(true),
  flashOnPageChange(false),
  // Slider ticks represent 100 ms.
  flashDuration(1),
  flashPageInterval(1),
  flashColor(FlashColor.black),
  customBrightness(false),
  // Negative values dim with an overlay; positive values require native window brightness.
  customBrightnessValue(0),
  customColorFilter(false),
  // Packed ARGB int.
  colorFilterValue(0),
  colorFilterBlendMode(ColorFilterBlendMode.defaultBlend),
  grayscale(false),
  invertedColors(false);

  const DBKeys(this.initial);

  final dynamic initial;
}

enum DBStoreName { settings }
