// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

/// Pure multi-chapter display list for the paged viewer.
///
/// The paged viewport shows prev/current/next chapters in ONE continuous pager
/// (like Komikku's PagerViewer) instead of rebuilding the reader per chapter.
/// This composes each loaded chapter's [SpreadMapping] into a single display
/// list, inserting a virtual transition entry between chapters, and translates
/// display-index ↔ (chapterId, raw page). Kept pure (no Flutter deps) so the
/// index contract is unit-tested.
library;

import 'paged_spread_mapping.dart';

/// One loaded chapter in the window: its spread mapping plus the raw page URLs
/// the spreads address.
class WindowChapter {
  const WindowChapter({
    required this.chapterId,
    required this.chapterName,
    required this.mapping,
    required this.pages,
    this.hasGapBefore = false,
  });

  final int chapterId;
  final String chapterName;
  final SpreadMapping mapping;
  final List<String> pages;

  /// True when there are missing (unloaded/absent) chapters between this chapter
  /// and the previous one in the window — forces a transition entry even when
  /// transitions are otherwise seamless.
  final bool hasGapBefore;
}

/// One position in the paged display list: either a spread of a chapter's pages
/// or a virtual chapter-boundary transition.
sealed class DisplayItem {
  const DisplayItem();
}

/// A spread (single page, double-page pair, or split-wide half) belonging to
/// [chapterId]; [entry] addresses that chapter's raw pages.
class SpreadDisplay extends DisplayItem {
  const SpreadDisplay({required this.chapterId, required this.entry});

  final int chapterId;
  final SpreadEntry entry;

  @override
  bool operator ==(Object other) =>
      other is SpreadDisplay &&
      other.chapterId == chapterId &&
      other.entry == entry;

  @override
  int get hashCode => Object.hash(chapterId, entry);

  @override
  String toString() => 'SpreadDisplay($chapterId, $entry)';
}

/// A virtual chapter-boundary card. [fromChapterId] is the chapter being left
/// (null at the very start of the window), [toChapterId] the one entered (null
/// at the very end / when the neighbour isn't loaded yet).
class TransitionDisplay extends DisplayItem {
  const TransitionDisplay({this.fromChapterId, this.toChapterId});

  final int? fromChapterId;
  final int? toChapterId;

  bool get isStart => fromChapterId == null;
  bool get isEnd => toChapterId == null;

  @override
  bool operator ==(Object other) =>
      other is TransitionDisplay &&
      other.fromChapterId == fromChapterId &&
      other.toChapterId == toChapterId;

  @override
  int get hashCode => Object.hash(fromChapterId, toChapterId);

  @override
  String toString() => 'TransitionDisplay($fromChapterId -> $toChapterId)';
}

/// The built multi-chapter display list plus the display ↔ (chapter, raw)
/// translation the viewer needs.
class PagedDisplayWindow {
  const PagedDisplayWindow(this.items, this._chapters);

  final List<DisplayItem> items;
  final List<WindowChapter> _chapters;

  int get length => items.length;
  bool get isEmpty => items.isEmpty;

  List<WindowChapter> get chapters => _chapters;

  WindowChapter? chapterById(int chapterId) {
    for (final c in _chapters) {
      if (c.chapterId == chapterId) return c;
    }
    return null;
  }

  /// The page URLs for the chapter shown at [displayIndex], or null for a
  /// transition / out-of-range slot.
  List<String>? pagesAt(int displayIndex) {
    final item = _itemAt(displayIndex);
    if (item is! SpreadDisplay) return null;
    return chapterById(item.chapterId)?.pages;
  }

  DisplayItem? _itemAt(int displayIndex) {
    if (displayIndex < 0 || displayIndex >= items.length) return null;
    return items[displayIndex];
  }

  /// display position → the (chapter, furthest raw page) it shows, for
  /// read-progress. Null for a transition slot or out-of-range index.
  ({int chapterId, int raw})? displayToChapterProgressRaw(int displayIndex) {
    final item = _itemAt(displayIndex);
    if (item is! SpreadDisplay) return null;
    return (chapterId: item.chapterId, raw: item.entry.progressRaw);
  }

  /// display position → the (chapter, reading-first raw page) it shows — the
  /// seekbar contract. Null for a transition slot or out-of-range index.
  ({int chapterId, int raw})? displayToChapterRaw(int displayIndex) {
    final item = _itemAt(displayIndex);
    if (item is! SpreadDisplay) return null;
    return (chapterId: item.chapterId, raw: item.entry.primaryRaw);
  }

  /// (chapter, raw) → the display position that shows it. Matches either page of
  /// a pair. Returns -1 when the chapter isn't in the window.
  int chapterRawToDisplay(int chapterId, int rawIndex) {
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item is SpreadDisplay &&
          item.chapterId == chapterId &&
          (item.entry.first.raw == rawIndex ||
              item.entry.second?.raw == rawIndex)) {
        return i;
      }
    }
    return -1;
  }

  /// The first display position belonging to [chapterId], or -1 if absent.
  int firstDisplayOf(int chapterId) {
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item is SpreadDisplay && item.chapterId == chapterId) return i;
    }
    return -1;
  }

  /// The last display position belonging to [chapterId], or -1 if absent.
  int lastDisplayOf(int chapterId) {
    for (var i = items.length - 1; i >= 0; i--) {
      final item = items[i];
      if (item is SpreadDisplay && item.chapterId == chapterId) return i;
    }
    return -1;
  }
}

/// Builds the multi-chapter display list from an ordered (reading order) list of
/// loaded chapters.
///
/// - A transition entry is inserted between two consecutive chapters when
///   [forceTransition] is set (the `alwaysShowChapterTransition` setting) or the
///   later chapter reports [WindowChapter.hasGapBefore]. Otherwise the crossing
///   is seamless (last spread of one chapter directly precedes the first of the
///   next), matching Komikku's PagerViewerAdapter.
/// - [leadingTransition] / [trailingTransition] add a boundary card before the
///   first / after the last chapter — used at the window edges where a further
///   chapter exists to load, or to show end/start-of-manga.
PagedDisplayWindow buildPagedDisplayWindow({
  required List<WindowChapter> chapters,
  required bool forceTransition,
  bool leadingTransition = false,
  bool trailingTransition = false,
}) {
  final items = <DisplayItem>[];
  if (chapters.isEmpty) return PagedDisplayWindow(items, chapters);

  if (leadingTransition) {
    items.add(TransitionDisplay(toChapterId: chapters.first.chapterId));
  }

  for (var c = 0; c < chapters.length; c++) {
    final chapter = chapters[c];
    if (c > 0 && (forceTransition || chapter.hasGapBefore)) {
      items.add(TransitionDisplay(
        fromChapterId: chapters[c - 1].chapterId,
        toChapterId: chapter.chapterId,
      ));
    }
    for (final entry in chapter.mapping.entries) {
      items.add(SpreadDisplay(chapterId: chapter.chapterId, entry: entry));
    }
  }

  if (trailingTransition) {
    items.add(TransitionDisplay(fromChapterId: chapters.last.chapterId));
  }

  return PagedDisplayWindow(items, chapters);
}
