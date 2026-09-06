// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../abstracts/value_enum.dart';
import '../utils/extensions/custom_extensions.dart';

enum AuthType {
  none,
  basic,
  simpleLogin,
  uiLogin;

  String toLocale(BuildContext context) => switch (this) {
        AuthType.none => context.l10n.authTypeNone,
        AuthType.basic => context.l10n.authTypeBasic,
        AuthType.simpleLogin => context.l10n.authTypeSimpleLogin,
        AuthType.uiLogin => context.l10n.authTypeUiLogin,
      };
}

enum ReaderMode {
  defaultReader,
  continuousVertical,
  singleHorizontalLTR,
  singleHorizontalRTL,
  continuousHorizontalLTR,
  continuousHorizontalRTL,
  singleVertical,
  webtoon;

  String toLocale(BuildContext context) => switch (this) {
        ReaderMode.defaultReader => context.l10n.readerModeDefaultReader,
        ReaderMode.continuousVertical =>
          context.l10n.readerModeContinuousVertical,
        ReaderMode.singleHorizontalLTR =>
          context.l10n.readerModeSingleHorizontalLTR,
        ReaderMode.singleHorizontalRTL =>
          context.l10n.readerModeSingleHorizontalRTL,
        ReaderMode.continuousHorizontalLTR =>
          context.l10n.readerModeContinuousHorizontalLTR,
        ReaderMode.continuousHorizontalRTL =>
          context.l10n.readerModeContinuousHorizontalRTL,
        ReaderMode.singleVertical => context.l10n.readerModeSingleVertical,
        ReaderMode.webtoon => context.l10n.readerModeWebtoon
      };
}

enum ReaderNavigationLayout {
  // Declaration order is the stored value — these persist by index, so this
  // list is append-only. Use [displayOrder] for anything user-facing.
  defaultNavigation,
  lShaped,
  rightAndLeft,
  edge,
  kindlish,
  disabled;

  /// Komikku's order (`ReaderPreferences.TapZones`), which differs from the
  /// declaration order above.
  static const List<ReaderNavigationLayout> displayOrder = [
    ReaderNavigationLayout.defaultNavigation,
    ReaderNavigationLayout.lShaped,
    ReaderNavigationLayout.kindlish,
    ReaderNavigationLayout.edge,
    ReaderNavigationLayout.rightAndLeft,
    ReaderNavigationLayout.disabled,
  ];

  String toLocale(BuildContext context) => switch (this) {
        ReaderNavigationLayout.defaultNavigation =>
          context.l10n.readerNavigationLayoutDefault,
        ReaderNavigationLayout.lShaped =>
          context.l10n.readerNavigationLayoutLShaped,
        ReaderNavigationLayout.rightAndLeft =>
          context.l10n.readerNavigationLayoutRightAndLeft,
        ReaderNavigationLayout.edge => context.l10n.readerNavigationLayoutEdge,
        ReaderNavigationLayout.kindlish =>
          context.l10n.readerNavigationLayoutKindlish,
        ReaderNavigationLayout.disabled =>
          context.l10n.readerNavigationLayoutDisabled
      };
}

/// Reader rotation lock. defaultRotation
/// means "leave the platform alone" so existing users see zero change.
enum ReaderOrientation {
  defaultRotation,
  free,
  portrait,
  landscape,
  lockedPortrait,
  lockedLandscape,
  reversePortrait;

  String toLocale(BuildContext context) => switch (this) {
        ReaderOrientation.defaultRotation =>
          context.l10n.readerOrientationDefault,
        ReaderOrientation.free => context.l10n.readerOrientationFree,
        ReaderOrientation.portrait => context.l10n.readerOrientationPortrait,
        ReaderOrientation.landscape => context.l10n.readerOrientationLandscape,
        ReaderOrientation.lockedPortrait =>
          context.l10n.readerOrientationLockedPortrait,
        ReaderOrientation.lockedLandscape =>
          context.l10n.readerOrientationLockedLandscape,
        ReaderOrientation.reversePortrait =>
          context.l10n.readerOrientationReversePortrait,
      };
}

/// 4-value tap-zone inversion. Successor of the
/// legacy invertTap bool: true→both, false→none; the old key is never rewritten.
enum TapInvert {
  none,
  horizontal,
  vertical,
  both;

  static TapInvert fromLegacyInvert(bool? invert) =>
      invert.ifNull() ? TapInvert.both : TapInvert.none;

  bool get invertsHorizontal =>
      this == TapInvert.horizontal || this == TapInvert.both;
  bool get invertsVertical =>
      this == TapInvert.vertical || this == TapInvert.both;

  /// Swaps the left/right zones. Right-and-Left is a spatial layout, so a
  /// right-to-left series has to mirror it: tapping the right edge goes back.
  TapInvert get horizontallyFlipped => switch (this) {
        TapInvert.none => TapInvert.horizontal,
        TapInvert.horizontal => TapInvert.none,
        TapInvert.vertical => TapInvert.both,
        TapInvert.both => TapInvert.vertical,
      };

  String toLocale(BuildContext context) => switch (this) {
        TapInvert.none => context.l10n.readerTapInvertNone,
        TapInvert.horizontal => context.l10n.readerTapInvertHorizontal,
        TapInvert.vertical => context.l10n.readerTapInvertVertical,
        TapInvert.both => context.l10n.readerTapInvertBoth,
      };
}

/// Paged image scale (default fit-screen).
enum ImageScaleType {
  fitScreen,
  stretch,
  fitWidth,
  fitHeight,
  originalSize,
  smartFit;

  String toLocale(BuildContext context) => switch (this) {
        ImageScaleType.fitScreen => context.l10n.imageScaleTypeFitScreen,
        ImageScaleType.stretch => context.l10n.imageScaleTypeStretch,
        ImageScaleType.fitWidth => context.l10n.imageScaleTypeFitWidth,
        ImageScaleType.fitHeight => context.l10n.imageScaleTypeFitHeight,
        ImageScaleType.originalSize => context.l10n.imageScaleTypeOriginalSize,
        ImageScaleType.smartFit => context.l10n.imageScaleTypeSmartFit,
      };

  /// Paged page render: the BoxFit + decode-size hint for a page image on a
  /// [width]×[height] screen. smartFit ≈ fit-width (most manga pages are tall).
  (BoxFit, Size?) pagedFit(double width, double height) => switch (this) {
        ImageScaleType.fitScreen => (BoxFit.contain, Size.fromHeight(height)),
        ImageScaleType.stretch => (BoxFit.fill, Size(width, height)),
        ImageScaleType.fitWidth => (BoxFit.fitWidth, Size.fromWidth(width)),
        ImageScaleType.fitHeight => (BoxFit.fitHeight, Size.fromHeight(height)),
        ImageScaleType.originalSize => (BoxFit.contain, null),
        ImageScaleType.smartFit => (BoxFit.fitWidth, Size.fromWidth(width)),
      };

  /// pagedFit above still returns BoxFit.contain; the zoom controller applies
  /// the real 1:1 scale (Mihon: a minimum zoom level, not a fit mode).
  bool get pagesAtNaturalSize => this == ImageScaleType.originalSize;
}

/// Paged zoom start position (default automatic).
enum ZoomStart {
  automatic,
  left,
  right,
  center;

  String toLocale(BuildContext context) => switch (this) {
        ZoomStart.automatic => context.l10n.zoomStartAutomatic,
        ZoomStart.left => context.l10n.zoomStartLeft,
        ZoomStart.right => context.l10n.zoomStartRight,
        ZoomStart.center => context.l10n.zoomStartCenter,
      };
}

/// Paged single/double-page layout (default automatic).
enum PageLayout {
  singlePage,
  doublePages,
  automatic;

  String toLocale(BuildContext context) => switch (this) {
        PageLayout.singlePage => context.l10n.pageLayoutSinglePage,
        PageLayout.doublePages => context.l10n.pageLayoutDoublePages,
        PageLayout.automatic => context.l10n.pageLayoutAutomatic,
      };
}

/// Foldable dead-space spacer (default none).
enum CenterMarginType {
  none,
  doublePage,
  widePage,
  doubleAndWide;

  String toLocale(BuildContext context) => switch (this) {
        CenterMarginType.none => context.l10n.centerMarginNone,
        CenterMarginType.doublePage => context.l10n.centerMarginDoublePages,
        CenterMarginType.widePage => context.l10n.centerMarginWidePages,
        CenterMarginType.doubleAndWide =>
          context.l10n.centerMarginDoubleAndWide,
      };
}

/// Reader page background. Declaration order matches
/// the stored ints 0-3; the chip row shows Black/Gray/White/Auto.
enum ReaderBackgroundColor {
  white,
  black,
  gray,
  automatic;

  String toLocale(BuildContext context) => switch (this) {
        ReaderBackgroundColor.white => context.l10n.backgroundColorWhite,
        ReaderBackgroundColor.black => context.l10n.backgroundColorBlack,
        ReaderBackgroundColor.gray => context.l10n.backgroundColorGray,
        ReaderBackgroundColor.automatic => context.l10n.backgroundColorAuto,
      };

  /// Gray is the literal 0x202125; automatic maps
  /// (dark theme → gray, light → white).
  Color color(BuildContext context) => switch (this) {
        ReaderBackgroundColor.white => Colors.white,
        ReaderBackgroundColor.black => Colors.black,
        ReaderBackgroundColor.gray => const Color(0xFF202125),
        ReaderBackgroundColor.automatic =>
          Theme.of(context).colorScheme.brightness == Brightness.dark
              ? const Color(0xFF202125)
              : Colors.white,
      };
}

/// Flash-on-page-change color. whiteBlack = white for the
/// first half of the flash, black for the second.
enum FlashColor {
  black,
  white,
  whiteBlack;

  String toLocale(BuildContext context) => switch (this) {
        FlashColor.black => context.l10n.flashColorBlack,
        FlashColor.white => context.l10n.flashColorWhite,
        FlashColor.whiteBlack => context.l10n.flashColorWhiteBlack,
      };
}

/// Fraction of the viewport advanced per keyboard/manual scroll step.
enum ReaderScrollAmount {
  tiny(0.10),
  small(0.25),
  medium(0.75),
  large(0.95);

  const ReaderScrollAmount(this.fraction);

  final double fraction;

  String toLocale(BuildContext context) => switch (this) {
        ReaderScrollAmount.tiny => context.l10n.scrollAmountTiny,
        ReaderScrollAmount.small => context.l10n.scrollAmountSmall,
        ReaderScrollAmount.medium => context.l10n.scrollAmountMedium,
        ReaderScrollAmount.large => context.l10n.scrollAmountLarge,
      };
}

/// Custom color-filter blend (order 0-5). Native Android
/// gates the last three behind API level P+; Flutter's BlendMode supports all
/// six everywhere, so no gate. "Multiply" is Compose Modulate (src×dst).
enum ColorFilterBlendMode {
  defaultBlend(BlendMode.srcOver),
  multiply(BlendMode.modulate),
  screen(BlendMode.screen),
  overlay(BlendMode.overlay),
  lighten(BlendMode.lighten),
  darken(BlendMode.darken);

  const ColorFilterBlendMode(this.blendMode);

  final BlendMode blendMode;

  String toLocale(BuildContext context) => switch (this) {
        ColorFilterBlendMode.defaultBlend =>
          context.l10n.colorFilterModeDefault,
        ColorFilterBlendMode.multiply => context.l10n.colorFilterModeMultiply,
        ColorFilterBlendMode.screen => context.l10n.colorFilterModeScreen,
        ColorFilterBlendMode.overlay => context.l10n.colorFilterModeOverlay,
        ColorFilterBlendMode.lighten => context.l10n.colorFilterModeLighten,
        ColorFilterBlendMode.darken => context.l10n.colorFilterModeDarken,
      };
}

/// Long-strip scale: fit, ratio-capped column, or native-size pages.
// Persisted by index — append only.
enum WebtoonScaleType {
  fitScreen,
  ratio4to3,
  ratio3to2,
  ratio16to9,
  ratio20to9,
  originalSize;

  String toLocale(BuildContext context) => switch (this) {
        WebtoonScaleType.fitScreen => context.l10n.webtoonScaleTypeFitScreen,
        WebtoonScaleType.ratio4to3 => context.l10n.webtoonScaleTypeRatio4to3,
        WebtoonScaleType.ratio3to2 => context.l10n.webtoonScaleTypeRatio3to2,
        WebtoonScaleType.ratio16to9 => context.l10n.webtoonScaleTypeRatio16to9,
        WebtoonScaleType.ratio20to9 => context.l10n.webtoonScaleTypeRatio20to9,
        WebtoonScaleType.originalSize =>
          context.l10n.webtoonScaleTypeOriginalSize,
      };

  /// Target column width/height ratio. 0 → no strip-level cap (fitScreen, and
  /// originalSize, whose per-page cap lives in the renderer).
  double get _ratio => switch (this) {
        WebtoonScaleType.fitScreen => 0,
        WebtoonScaleType.ratio4to3 => 3 / 4,
        WebtoonScaleType.ratio3to2 => 2 / 3,
        WebtoonScaleType.ratio16to9 => 9 / 16,
        WebtoonScaleType.ratio20to9 => 9 / 20,
        WebtoonScaleType.originalSize => 0,
      };

  /// Max long-strip content width for a [screenWidth]×[screenHeight] viewport.
  /// Caps the strip to the target aspect only when the screen is wider than
  /// that column (shrinks iff screenRatio > desiredRatio); otherwise
  /// full width. Pure/render-only — no scroll math.
  double maxContentWidth(double screenWidth, double screenHeight) {
    final ratio = _ratio;
    if (ratio <= 0) return screenWidth;
    final desiredWidth = screenHeight * ratio;
    return desiredWidth < screenWidth ? desiredWidth : screenWidth;
  }
}

enum MangaSort {
  alphabetical,
  dateAdded,
  unread,
  lastUpdated,
  lastChapterDate,
  totalChapters,
  lastRead,
  random,
  trackerScore,
  // Appended (NOT reordered) — MangaSort prefs are stored by enum index, so
  // reordering would corrupt saved sorts. Sort-tab display order is controlled
  // separately (see library_manga_organizer.dart).
  lastUpdate,
  rating;

  String toLocale(BuildContext context) => switch (this) {
        MangaSort.alphabetical => context.l10n.mangaSortAlphabetical,
        MangaSort.dateAdded => context.l10n.mangaSortDateAdded,
        MangaSort.unread => context.l10n.mangaSortUnread,
        MangaSort.lastUpdated => context.l10n.mangaSortLastUpdated,
        MangaSort.lastChapterDate => context.l10n.mangaSortLastChapterDate,
        MangaSort.totalChapters => context.l10n.mangaSortTotalChapters,
        MangaSort.lastRead => context.l10n.mangaSortLastRead,
        MangaSort.random => context.l10n.mangaSortRandom,
        MangaSort.trackerScore => context.l10n.mangaSortTrackerScore,
        MangaSort.lastUpdate => context.l10n.mangaSortLastUpdate,
        MangaSort.rating => context.l10n.mangaSortRating,
      };
}

enum ChapterSort {
  source,
  uploadDate,
  fetchedDate,
  // Appended last: saved prefs store the index into [values].
  chapterNumber,
  alphabetical;

  String toLocale(BuildContext context) => switch (this) {
        ChapterSort.source => context.l10n.chapterSortSource,
        ChapterSort.fetchedDate => context.l10n.chapterSortFetchedDate,
        ChapterSort.uploadDate => context.l10n.chapterSortUploadDate,
        ChapterSort.chapterNumber => context.l10n.chapterSortChapterNumber,
        ChapterSort.alphabetical => context.l10n.chapterSortAlphabetical,
      };
}

enum ChapterDisplay {
  sourceTitle,
  chapterNumber;

  String toLocale(BuildContext context) => switch (this) {
        ChapterDisplay.sourceTitle => context.l10n.chapterDisplaySourceTitle,
        ChapterDisplay.chapterNumber =>
          context.l10n.chapterDisplayChapterNumber,
      };
}

enum DisplayMode {
  grid(Icons.grid_view_rounded),
  list(Icons.view_list_rounded),
  descriptiveList(Icons.view_list_rounded),
  coverOnly(Icons.view_comfy_rounded),
  // Appended last: saved prefs store the index into [values].
  comfortableGrid(Icons.view_module_rounded),
  ;

  static const List<DisplayMode> sourceDisplayList = [
    DisplayMode.grid,
    DisplayMode.list
  ];

  /// Menu order for the library display tab (differs from declaration order,
  /// which is frozen by persisted indexes).
  static const List<DisplayMode> libraryDisplayList = [
    DisplayMode.list,
    DisplayMode.descriptiveList,
    DisplayMode.grid,
    DisplayMode.comfortableGrid,
    DisplayMode.coverOnly,
  ];

  final IconData icon;
  const DisplayMode(this.icon);

  /// Gates the column slider and the grid-style selector in the Display tab.
  bool get isGrid =>
      this == DisplayMode.grid ||
      this == DisplayMode.comfortableGrid ||
      this == DisplayMode.coverOnly;

  String toLocale(BuildContext context) => switch (this) {
        DisplayMode.grid => context.l10n.displayModeGrid,
        DisplayMode.list => context.l10n.displayModeList,
        DisplayMode.descriptiveList => context.l10n.displayModeDescriptiveList,
        DisplayMode.coverOnly => context.l10n.displayModeCoverOnly,
        DisplayMode.comfortableGrid => context.l10n.displayModeComfortableGrid,
      };

  /// The library offers three grid variants, so plain [grid] reads as
  /// "Compact grid" there; Browse only has grid/list and keeps [toLocale].
  String toLibraryLocale(BuildContext context) => this == DisplayMode.grid
      ? context.l10n.displayModeCompactGrid
      : toLocale(context);
}

/// Unread badge presentation. Persisted by index, so the order is frozen.
enum UnreadBadgeMode {
  count,
  dot,
  hidden;

  bool get isVisible => this != UnreadBadgeMode.hidden;

  String toLocale(BuildContext context) => switch (this) {
        UnreadBadgeMode.count => context.l10n.unreadBadgeModeCount,
        UnreadBadgeMode.dot => context.l10n.unreadBadgeModeDot,
        UnreadBadgeMode.hidden => context.l10n.unreadBadgeModeHidden,
      };
}

/// Which corner of a cover a badge clusters into.
enum BadgeSide { left, right }

/// Every badge that can be drawn on a library cover, in shipped drag-order.
///
/// [id] is what gets persisted in `badgeOrder` / `badgeRightSide` — never the
/// enum index — so inserting a badge here can't repoint a saved layout.
enum LibraryBadge {
  unread('unread'),
  downloaded('downloaded'),
  onDevice('onDevice'),
  language('language'),
  source('source');

  const LibraryBadge(this.id);
  final String id;

  static LibraryBadge? fromId(String id) {
    for (final b in LibraryBadge.values) {
      if (b.id == id) return b;
    }
    return null;
  }

  String toLocale(BuildContext context) => switch (this) {
        LibraryBadge.unread => context.l10n.unread,
        LibraryBadge.downloaded => context.l10n.downloaded,
        LibraryBadge.onDevice => context.l10n.onDevice,
        LibraryBadge.language => context.l10n.languageBadge,
        LibraryBadge.source => context.l10n.sourceBadge,
      };
}

/// Which widget renders a grouped library. Persisted by index.
///
/// Orthogonal to `categoryTabs` / `sectionHeadersShowAllCategories`, which
/// modify whichever style is active — see `_groupedBody` in library_screen.
enum LibraryGroupStyle {
  /// One page per group, behind a swipeable `TabBarView`.
  tabs,

  /// A single continuous scroll, each group under a sticky header.
  headers;

  String toLocale(BuildContext context) => switch (this) {
        LibraryGroupStyle.tabs => context.l10n.groupStyleTabs,
        LibraryGroupStyle.headers => context.l10n.groupStyleHeaders,
      };
}

/// Cover geometry for the library's grid modes. Persisted by index.
enum LibraryGridStyle {
  /// Every cover is cropped into the same fixed 2:3 cell.
  uniform(Icons.grid_view_rounded),

  /// Fixed cell width, cover height follows the art (capped). Rows align to
  /// their tallest cover.
  nonUniform(Icons.grid_goldenratio_rounded),

  /// Masonry: each column packs independently.
  staggered(Icons.dashboard_rounded);

  const LibraryGridStyle(this.icon);
  final IconData icon;

  /// True when tiles size themselves from the cover art instead of filling a
  /// fixed cell.
  bool get isFreeform => this != LibraryGridStyle.uniform;

  String toLocale(BuildContext context) => switch (this) {
        LibraryGridStyle.uniform => context.l10n.gridStyleUniform,
        LibraryGridStyle.nonUniform => context.l10n.gridStyleNonUniform,
        LibraryGridStyle.staggered => context.l10n.gridStyleStaggered,
      };
}

/// Chapter list presentation on the manga details page (per-series, stored in
/// manga meta).
enum ChapterListMode {
  list(Icons.view_list_rounded),
  grid(Icons.grid_view_rounded);

  const ChapterListMode(this.icon);
  final IconData icon;

  String toLocale(BuildContext context) => switch (this) {
        ChapterListMode.list => context.l10n.displayModeList,
        ChapterListMode.grid => context.l10n.displayModeGrid,
      };
}

enum MangaStatus {
  unknown("UNKNOWN", Icons.block_outlined),
  ongoing("ONGOING", Icons.schedule_rounded),
  completed("COMPLETED", Icons.done_all_rounded),
  licensed("LICENSED", Icons.shield_rounded),
  publishingFinished("PUBLISHING_FINISHED", Icons.publish_rounded),
  cancelled("CANCELLED", Icons.cancel_rounded),
  onHiatus("ON_HIATUS", Icons.pause_circle_rounded);

  final IconData icon;
  final String title;
  const MangaStatus(
    this.title,
    this.icon,
  );
  static final _statusMap = <String, MangaStatus>{
    for (MangaStatus status in MangaStatus.values) status.title: status
  };
  static MangaStatus fromJson(String status) =>
      _statusMap[status] ?? MangaStatus.unknown;
  static String toJson(MangaStatus? status) =>
      status?.title ?? MangaStatus.unknown.title;

  String toLocale(BuildContext context) => switch (this) {
        MangaStatus.unknown => context.l10n.mangaStatusUnknown,
        MangaStatus.ongoing => context.l10n.mangaStatusOngoing,
        MangaStatus.completed => context.l10n.mangaStatusCompleted,
        MangaStatus.licensed => context.l10n.mangaStatusLicensed,
        MangaStatus.publishingFinished =>
          context.l10n.mangaStatusPublishingFinished,
        MangaStatus.cancelled => context.l10n.mangaStatusCancelled,
        MangaStatus.onHiatus => context.l10n.mangaStatusOnHiatus
      };
}

@JsonEnum(valueField: 'value')
enum IncludeOrExclude implements ValueEnum {
  include("INCLUDE"),
  exclude("EXCLUDE"),
  unset("UNSET");

  const IncludeOrExclude(this.value);

  @override
  final String value;
}

/// Global-search source scope: search only pinned sources, or all of them.
enum GlobalSearchSourceFilter { pinned, all }

/// Controls how consecutive chapters from the same manga are grouped on the
/// Updates page. [disabled] = flat list (legacy behaviour); [collapsed] =
/// grouped and folded by default; [expanded] = grouped and unfolded by default.
enum UpdatesGroupingMode {
  disabled,
  collapsed,
  expanded;

  String toLocale(BuildContext context) => switch (this) {
        UpdatesGroupingMode.disabled =>
          context.l10n.updatesGroupingModeDisabled,
        UpdatesGroupingMode.collapsed =>
          context.l10n.updatesGroupingModeCollapsed,
        UpdatesGroupingMode.expanded =>
          context.l10n.updatesGroupingModeExpanded,
      };
}
