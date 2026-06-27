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
  mangaSortDirection(true), // asc=true, dsc=false
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
  hideEmptyCategory(false),
  // When false (default, Mihon-style), opening an entry shows the chapters the
  // server already has, without re-scraping the source. When true, also refresh
  // from the source on open.
  refreshChaptersFromSource(false),
  pinchToZoom(true),
  // Default to edge-to-edge like Komikku (fullscreen=true + drawUnderCutout):
  // the webtoon strip fills the whole screen, including the status-bar / camera
  // -cutout row at the top. Users can re-enable insets in reader settings.
  readerIgnoreSafeArea(true),
  appTheme(AppTheme.indigoNight),
  customThemeColor(0xFF7C7BFF),
  historyEnabled(true),
  historyRetentionDays(90),
  // Timeout Settings
  serverRequestTimeout(5000), // milliseconds
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
  // Restrict background downloads to Wi-Fi connections only.
  downloadOnlyOverWifi(false),
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
  ;

  const DBKeys(this.initial);

  final dynamic initial;
}

enum DBStoreName { settings }
