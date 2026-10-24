// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
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
    ReaderMode.continuousVertical => context.l10n.readerModeContinuousVertical,
    ReaderMode.singleHorizontalLTR =>
      context.l10n.readerModeSingleHorizontalLTR,
    ReaderMode.singleHorizontalRTL =>
      context.l10n.readerModeSingleHorizontalRTL,
    ReaderMode.continuousHorizontalLTR =>
      context.l10n.readerModeContinuousHorizontalLTR,
    ReaderMode.continuousHorizontalRTL =>
      context.l10n.readerModeContinuousHorizontalRTL,
    ReaderMode.singleVertical => context.l10n.readerModeSingleVertical,
    ReaderMode.webtoon => context.l10n.readerModeWebtoon,
  };
}

enum ReaderNavigationLayout {
  // Persisted by index: append only; use displayOrder for presentation.
  defaultNavigation,
  lShaped,
  rightAndLeft,
  edge,
  kindlish,
  disabled;

  /// Display order differs from the persisted declaration order.
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
      context.l10n.readerNavigationLayoutDisabled,
  };
}

/// defaultRotation leaves platform rotation unchanged.
enum ReaderOrientation {
  defaultRotation,
  free,
  portrait,
  landscape,
  lockedPortrait,
  lockedLandscape,
  reversePortrait;

  String toLocale(BuildContext context) => switch (this) {
    ReaderOrientation.defaultRotation => context.l10n.readerOrientationDefault,
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

/// Legacy invertTap maps true to both and false to none; its key is never rewritten.
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

  /// Mirrors spatial left/right tap zones for right-to-left series.
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

  /// smartFit uses fit-width; returns fit and decode size for the viewport.
  (BoxFit, Size?) pagedFit(double width, double height) => switch (this) {
    ImageScaleType.fitScreen => (BoxFit.contain, Size.fromHeight(height)),
    ImageScaleType.stretch => (BoxFit.fill, Size(width, height)),
    ImageScaleType.fitWidth => (BoxFit.fitWidth, Size.fromWidth(width)),
    ImageScaleType.fitHeight => (BoxFit.fitHeight, Size.fromHeight(height)),
    ImageScaleType.originalSize => (BoxFit.contain, null),
    ImageScaleType.smartFit => (BoxFit.fitWidth, Size.fromWidth(width)),
  };

  /// The zoom controller applies native 1:1 scale; pagedFit still returns BoxFit.contain.
  bool get pagesAtNaturalSize => this == ImageScaleType.originalSize;
}

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

enum CenterMarginType {
  none,
  doublePage,
  widePage,
  doubleAndWide;

  String toLocale(BuildContext context) => switch (this) {
    CenterMarginType.none => context.l10n.centerMarginNone,
    CenterMarginType.doublePage => context.l10n.centerMarginDoublePages,
    CenterMarginType.widePage => context.l10n.centerMarginWidePages,
    CenterMarginType.doubleAndWide => context.l10n.centerMarginDoubleAndWide,
  };
}

/// Declaration order matches stored values 0–3.
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

/// whiteBlack flashes white first, then black.
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

/// Multiply uses Compose Modulate (src×dst); all blends are available on every platform.
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
    ColorFilterBlendMode.defaultBlend => context.l10n.colorFilterModeDefault,
    ColorFilterBlendMode.multiply => context.l10n.colorFilterModeMultiply,
    ColorFilterBlendMode.screen => context.l10n.colorFilterModeScreen,
    ColorFilterBlendMode.overlay => context.l10n.colorFilterModeOverlay,
    ColorFilterBlendMode.lighten => context.l10n.colorFilterModeLighten,
    ColorFilterBlendMode.darken => context.l10n.colorFilterModeDarken,
  };
}

/// Persisted by index: append only.
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
    WebtoonScaleType.originalSize => context.l10n.webtoonScaleTypeOriginalSize,
  };

  /// Zero disables the strip-level cap; originalSize is capped per page.
  double get _ratio => switch (this) {
    WebtoonScaleType.fitScreen => 0,
    WebtoonScaleType.ratio4to3 => 3 / 4,
    WebtoonScaleType.ratio3to2 => 2 / 3,
    WebtoonScaleType.ratio16to9 => 9 / 16,
    WebtoonScaleType.ratio20to9 => 9 / 20,
    WebtoonScaleType.originalSize => 0,
  };

  /// Caps width to the target aspect ratio only when the viewport is wider.
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
  // Persisted by enum index: append only; display order is defined separately.
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
  // Persisted by index: append only.
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

/// Persisted by index: append only.
enum ChapterSwipeAction {
  toggleRead,
  toggleBookmark,
  download,
  disabled;

  String toLocale(BuildContext context) => switch (this) {
    ChapterSwipeAction.toggleRead => context.l10n.markAsRead,
    ChapterSwipeAction.toggleBookmark =>
      context.l10n.chapterSwipeBookmarkChapter,
    ChapterSwipeAction.download => context.l10n.download,
    ChapterSwipeAction.disabled => context.l10n.chapterSwipeDisabled,
  };
}

enum ChapterDisplay {
  sourceTitle,
  chapterNumber;

  String toLocale(BuildContext context) => switch (this) {
    ChapterDisplay.sourceTitle => context.l10n.chapterDisplaySourceTitle,
    ChapterDisplay.chapterNumber => context.l10n.chapterDisplayChapterNumber,
  };
}

enum DisplayMode {
  grid(FluentIcons.grid_24_regular),
  list(FluentIcons.apps_list_24_regular),
  descriptiveList(FluentIcons.apps_list_detail_24_regular),
  coverOnly(FluentIcons.image_multiple_24_regular),
  // Persisted by index: append only.
  comfortableGrid(FluentIcons.layout_cell_four_24_regular);

  static const List<DisplayMode> sourceDisplayList = [
    DisplayMode.grid,
    DisplayMode.list,
  ];

  /// Display order differs from the persisted declaration order.
  static const List<DisplayMode> libraryDisplayList = [
    DisplayMode.list,
    DisplayMode.descriptiveList,
    DisplayMode.grid,
    DisplayMode.comfortableGrid,
    DisplayMode.coverOnly,
  ];

  final IconData icon;
  const DisplayMode(this.icon);

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

  /// Library calls grid "Compact grid"; Browse retains the generic label.
  String toLibraryLocale(BuildContext context) => this == DisplayMode.grid
      ? context.l10n.displayModeCompactGrid
      : toLocale(context);
}

/// Persisted by index: append only.
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

enum BadgeSide { left, right }

/// Persisted by id, never enum index; inserting badges preserves saved layouts.
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

/// Persisted by index; categoryTabs and sectionHeadersShowAllCategories modify the active style.
enum LibraryGroupStyle {
  tabs,

  headers;

  String toLocale(BuildContext context) => switch (this) {
    LibraryGroupStyle.tabs => context.l10n.groupStyleTabs,
    LibraryGroupStyle.headers => context.l10n.groupStyleHeaders,
  };
}

/// Persisted by index.
enum LibraryGridStyle {
  uniform(FluentIcons.grid_24_regular),

  /// Rows align to the tallest cover; individual cover heights follow the art.
  nonUniform(FluentIcons.layout_column_three_24_regular),

  staggered(FluentIcons.board_24_regular);

  const LibraryGridStyle(this.icon);
  final IconData icon;

  bool get isFreeform => this != LibraryGridStyle.uniform;

  String toLocale(BuildContext context) => switch (this) {
    LibraryGridStyle.uniform => context.l10n.gridStyleUniform,
    LibraryGridStyle.nonUniform => context.l10n.gridStyleNonUniform,
    LibraryGridStyle.staggered => context.l10n.gridStyleStaggered,
  };
}

enum MangaStatus {
  unknown("UNKNOWN", FluentIcons.prohibited_24_regular),
  ongoing("ONGOING", FluentIcons.clock_24_regular),
  completed("COMPLETED", FluentIcons.checkmark_starburst_24_regular),
  licensed("LICENSED", FluentIcons.shield_24_regular),
  publishingFinished("PUBLISHING_FINISHED", FluentIcons.arrow_upload_24_regular),
  cancelled("CANCELLED", FluentIcons.dismiss_circle_24_regular),
  onHiatus("ON_HIATUS", FluentIcons.pause_circle_24_regular);

  final IconData icon;
  final String title;
  const MangaStatus(this.title, this.icon);
  static final _statusMap = <String, MangaStatus>{
    for (MangaStatus status in MangaStatus.values) status.title: status,
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
    MangaStatus.onHiatus => context.l10n.mangaStatusOnHiatus,
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

enum GlobalSearchSourceFilter { pinned, all }

/// disabled is flat; collapsed and expanded group chapters with the named initial state.
enum UpdatesGroupingMode {
  disabled,
  collapsed,
  expanded;

  String toLocale(BuildContext context) => switch (this) {
    UpdatesGroupingMode.disabled => context.l10n.updatesGroupingModeDisabled,
    UpdatesGroupingMode.collapsed => context.l10n.updatesGroupingModeCollapsed,
    UpdatesGroupingMode.expanded => context.l10n.updatesGroupingModeExpanded,
  };
}
