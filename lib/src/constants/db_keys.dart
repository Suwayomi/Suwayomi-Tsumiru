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
  serverPort(4567),
  serverPortToggle(true),
  // First-time onboarding: false until the wizard is finished. A one-time
  // migration seeds it true for installs that already have a server configured.
  onboardingComplete(false),
  sourceLanguageFilter(["all", "lastUsed", "en", "localsourcelang"]),
  extensionLanguageFilter(["installed", "update", "en", "all"]),
  sourceLastUsed(null),
  themeMode(ThemeMode.system),
  isTrueBlack(false),
  authType(AuthType.none),
  basicCredentials(null),
  authUsername(null),
  readerMode(ReaderMode.webtoon),
  readerPadding(0.0),
  readerMagnifierSize(1.0),
  readerNavigationLayout(ReaderNavigationLayout.disabled),
  invertTap(false),
  quickSearchToggle(true),
  swipeToggle(true),
  lastPageSwipeEnabled(false),
  infinityScrollingMode(true),
  scrollAnimation(true),
  showNSFW(true),
  downloadedBadge(false),
  unreadBadge(true),
  languageBadge(false),
  localBadge(false),
  sourceBadge(false),
  useLangIcon(false),
  // Library display: overlay a play button on covers that jumps straight into
  // the next unread chapter. Off by default, matching Suwayomi-WebUI.
  showContinueReadingButton(false),
  l10n(Locale('en')),
  mangaFilterDownloaded(null),
  mangaFilterOffline(null),
  mangaFilterUnread(null),
  mangaFilterCompleted(null),
  mangaFilterStarted(null),
  mangaFilterBookmarked(null),
  chapterFilterDownloaded(null),
  chapterFilterUnread(null),
  chapterFilterBookmarked(null),
  mangaSort(MangaSort.lastRead),
  // Default descending so the default Last-Read sort opens newest-read first
  // (last-read-descending). asc=true, dsc=false.
  mangaSortDirection(false),
  chapterSort(ChapterSort.source),
  chapterSortDirection(false), // asc=true, dsc=false
  libraryDisplayMode(DisplayMode.grid),
  sourceDisplayMode(DisplayMode.grid),
  gridMangaCoverWidth(192.0),
  readerOverlay(true),
  // Show the continuous-reader feedback snackbars ("loading next chapter",
  // "no more chapters", etc.). Off = a quiet reading experience.
  readerFeedbackToasts(true),
  volumeTap(false),
  volumeTapInvert(false),
  keepScreenOn(true),
  hideEmptyCategory(false),
  // When false (default), opening an entry shows the chapters the
  // server already has, without re-scraping the source. When true, also refresh
  // from the source on open.
  refreshChaptersFromSource(false),
  pinchToZoom(true),
  // Default to edge-to-edge (fullscreen=true + drawUnderCutout):
  // the webtoon strip fills the whole screen, including the status-bar / camera
  // -cutout row at the top. Users can re-enable insets in reader settings.
  readerIgnoreSafeArea(true),
  appTheme(AppTheme.indigoNight),
  customThemeColor(0xFF7C7BFF),
  historyEnabled(true),
  historyRetentionDays(90),
  // Timeout Settings
  // 30s matches Komikku's source read timeout; pages proxied live from a
  // source routinely exceed 5s on first fetch.
  serverRequestTimeout(30000), // milliseconds
  autoRefreshOnTimeout(false),
  autoRefreshRetryDelay(1000), // milliseconds
  // Offline safety-net settings
  offlineTimeEvictEnabled(false),
  offlineKeepDays(30),
  offlineStorageCapEnabled(false),
  offlineStorageCapMb(2000),
  // How many chapter pages download at once. Low by default: a self-hosted
  // server saturates fast and starts returning 500/503 under heavy parallelism.
  offlineDownloadConcurrency(2),
  // Restrict background downloads to Wi-Fi connections only. Default ON so a
  // fresh install never burns mobile data on downloads unless the user opts in.
  downloadOnlyOverWifi(true),
  // User-initiated pause of all ON-DEVICE downloads. Persisted (an explicit
  // pause shouldn't silently resume on restart); read synchronously by the
  // download starters to gate every restart path.
  offlineDownloadsPaused(false),
  // ON-DEVICE delete-on-read settings (frees device space; the server copy is
  // untouched). Independent of the server's "Delete chapters" settings.
  // whileReading: 0 = off, 1 = the just-read chapter, 2..5 = the Nth behind it.
  localDeleteWhileReading(0),
  localDeleteManuallyMarkedRead(false),
  localDeleteWithBookmark(false),
  // Lock phones to portrait (landscape on a phone currently looks broken). Off
  // by default — many readers prefer landscape; tablets/desktop ignore it.
  forcePortrait(false),
  // The release version the user chose to skip in the update prompt. The
  // prompt stays hidden until a release newer than this one appears.
  dismissedUpdateVersion(''),
  updateProgressAfterReading(true),
  updateProgressManualMarkRead(true),
  // Library grid: explicit column count per orientation. 0 = Auto (falls back
  // to the width-based delegate using gridMangaCoverWidth as the target size).
  libraryPortraitColumns(0),
  libraryLandscapeColumns(0),
  // Library Tabs section (Display sheet).
  // When false, the category tab bar is hidden even if >1 category exists.
  categoryTabs(true),
  // When true, categories marked as hidden are still shown as tabs.
  showHiddenCategories(false),
  // When true, each tab label appends "(N)" where N is the filtered manga count.
  categoryNumberOfItems(false),
  // How the library tabs are grouped: 0=by category (default), 1=by source,
  // 2=by status, 3=by track status (reserved; filled in Task 8), 4=ungrouped.
  libraryGroupType(0),
  mangaFilterLewd(null),
  filterCategories(false),
  filterCategoriesInclude(<String>[]),
  filterCategoriesExclude(<String>[]),
  // Seed for the Random library sort. Incrementing this re-rolls the order.
  librarySortRandomSeed(0),
  // Reader seekbar layout. When false (default), webtoon uses
  // the vertical side seekbar. When true, a horizontal bottom
  // seekbar is shown in all modes (including webtoon).
  forceHorizontalSeekbar(false),
  // Reader side seekbar handedness. When false (default), the vertical side
  // seekbar is anchored to the right edge. When true, it is anchored to the
  // left edge for left-handed reading.
  leftHandedVerticalSeekbar(false),
  // Webtoon/long-strip zoom gestures: double-tap zoom on, zoom-out below 1x
  // allowed (down to 0.5x) unless disabled.
  doubleTapToZoom(true),
  disableZoomOut(false),
  // Paged "Disable zoom in": turns off the paged viewer's zoom wrapper.
  disableZoomIn(false),
  // Auto Webtoon Mode: series whose tags/source say
  // long-strip read in webtoon mode when their per-series mode is Default.
  autoWebtoonMode(true),
  // Reader rotation lock. Default = never touch the platform.
  readerOrientation(ReaderOrientation.defaultRotation),
  // 4-value tap-zone invert. null initial keeps "unset" representable so the
  // legacy invertTap bool still decides for users who never set this.
  readerTapInvert(null),
  // Paged parity prefs. Persisted now,
  // consumed by the paged engine in a later increment.
  imageScaleType(ImageScaleType.fitScreen),
  zoomStart(ZoomStart.automatic),
  pageLayout(PageLayout.automatic),
  centerMarginType(CenterMarginType.none),
  landscapeZoom(true),
  navigateToPan(true),
  invertDoublePages(false),
  cropBorders(false),
  // Shared by the paged and long-strip sections.
  smallerTapZones(false),
  animatePageTransitions(true),
  // Wide-page handling. Split needs
  // page-list remapping, so it persists here and the engine wires it later;
  // rotate is live in the paged viewer.
  dualPageSplitPaged(false),
  dualPageInvertPaged(false),
  rotateWidePages(false),
  rotateWideInvert(false),
  // KEEP-style extra: show two pages side-by-side in landscape (inert).
  trueDualPageSpread(false),
  // Long-strip parity prefs; crop-borders is scoped per mode.
  webtoonScaleType(WebtoonScaleType.fitScreen),
  cropBordersWebtoon(false),
  cropBordersGaps(false),
  smoothAutoScroll(true),
  dualPageSplitWebtoon(false),
  dualPageInvertWebtoon(false),
  // Reader General tab (all global).
  readerBackgroundColor(ReaderBackgroundColor.black),
  showPageNumber(true),
  // Sub-toggle of the seekbar chain: keep the vertical side seekbar even on a
  // landscape phone (SY pref_show_vert_seekbar_landscape).
  landscapeVerticalSeekbar(false),
  readerFullscreen(true),
  // Only meaningful with fullscreen ON; needs platform window attrs (inert).
  drawUnderCutout(true),
  readWithLongTap(true),
  alwaysShowChapterTransition(true),
  flashOnPageChange(false),
  // Stored as slider ticks ×100 ms, converted to milliseconds internally.
  flashDuration(1),
  flashPageInterval(1),
  flashColor(FlashColor.black),
  // Custom filter tab (all global).
  customBrightness(false),
  // -75..100. Negatives dim via a black overlay; positives set the
  // window screen-brightness attr — no Flutter plugin, so persist-but-inert.
  customBrightnessValue(0),
  customColorFilter(false),
  // Packed ARGB int.
  colorFilterValue(0),
  colorFilterBlendMode(ColorFilterBlendMode.defaultBlend),
  grayscale(false),
  invertedColors(false),
  ;

  const DBKeys(this.initial);

  final dynamic initial;
}

enum DBStoreName { settings }
