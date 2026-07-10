// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../../../domain/chapter/chapter_model.dart';
import '../../../../../domain/chapter_page/chapter_page_model.dart';

/// Utility functions for the continuous reader modes.
///
/// Helpers fall into two groups:
///   * SPL-only: ``calculateVisibleArea`` is used by the single-chapter
///     SPL implementation in ``infinity_continuous_reader_mode.dart``
///     for "most-visible page" tracking against ``ItemPosition``.
///   * Shared: the multi-chapter helpers
///     (``getTotalPages``, ``isChapterBoundary``,
///     ``convertChapterIndexToGlobalIndex``, ``createChapterPagesDto``)
///     are used by the ListView-based multi-chapter reader.
class InfinityContinuousUtils {
  const InfinityContinuousUtils._();

  /// Visible fraction of an item position in [0, 1].
  static double calculateVisibleArea(ItemPosition position) {
    final double leadingEdge = position.itemLeadingEdge.clamp(0.0, 1.0);
    final double trailingEdge = position.itemTrailingEdge.clamp(0.0, 1.0);

    final double visibleStart = leadingEdge < 0 ? 0.0 : leadingEdge;
    final double visibleEnd = trailingEdge > 1 ? 1.0 : trailingEdge;

    return (visibleEnd - visibleStart).clamp(0.0, 1.0);
  }

  /// The global page index the reader is "on" for progress, given the visible
  /// [positions] (already filtered to those on screen) and [total] loaded pages.
  ///
  /// Normally the page showing the greatest visible area. But when the last
  /// page's bottom has reached the viewport bottom ([ItemPosition.itemTrailingEdge]
  /// <= 1.0), the reader is scrolled as far as it goes, so that last page is
  /// current even if a taller earlier page still shows more area. Without this,
  /// short trailing pages (e.g. a small credits page that lets three pages share
  /// the screen) leave progress stuck one short and the last chapter never marks
  /// read (#100). Returns null when nothing is visible.
  static int? selectCurrentIndex(
    List<ItemPosition> positions,
    int total, {
    required double minVisibleAreaThreshold,
  }) {
    if (positions.isEmpty) return null;

    // total - 1 is the last loaded page; itemTrailingEdge <= 1.0 means its
    // bottom sits at or above the viewport bottom, i.e. the end is reached.
    final lastPage = positions.where((p) => p.index == total - 1);
    if (total > 1 &&
        lastPage.isNotEmpty &&
        lastPage.first.itemTrailingEdge <= 1.0) {
      return total - 1;
    }

    ItemPosition? mostVisible;
    double bestArea = 0.0;
    for (final p in positions) {
      final area = calculateVisibleArea(p);
      if (area > bestArea && area > minVisibleAreaThreshold) {
        bestArea = area;
        mostVisible = p;
      }
    }
    mostVisible ??= positions.reduce(
      (a, b) => a.itemLeadingEdge.abs() <= b.itemLeadingEdge.abs() ? a : b,
    );
    return mostVisible.index;
  }

  /// Sum of pages across all loaded chapters.
  static int getTotalPages(
    List<({ChapterPagesDto pages, ChapterDto chapter, int chapterId})>
        loadedChapters,
  ) {
    return loadedChapters.fold(
      0,
      (sum, chapterData) => sum + chapterData.pages.pages.length,
    );
  }

  /// True if [index] is the first page of a chapter that has a chapter
  /// before it, or the last page of a chapter that has a chapter after
  /// it — used to decide where to render a chapter separator.
  static bool isChapterBoundary(
    int index,
    List<({ChapterPagesDto pages, ChapterDto chapter, int chapterId})>
        loadedChapters,
  ) {
    int currentIndex = 0;
    for (final chapterData in loadedChapters) {
      if (index == currentIndex && currentIndex > 0) {
        return true;
      }
      if (index == currentIndex + chapterData.pages.pages.length - 1 &&
          currentIndex + chapterData.pages.pages.length <
              getTotalPages(loadedChapters)) {
        return true;
      }
      currentIndex += chapterData.pages.pages.length;
    }
    return false;
  }

  /// Convert a chapter-relative page index for a given chapter into the
  /// global page index across all loaded chapters. Returns -1 if the
  /// chapter is not loaded.
  static int convertChapterIndexToGlobalIndex(
    int chapterIndex,
    List<({ChapterPagesDto pages, ChapterDto chapter, int chapterId})>
        loadedChapters,
    int chapterId,
  ) {
    int globalIndex = 0;
    for (final chapterData in loadedChapters) {
      if (chapterData.chapterId == chapterId) {
        return globalIndex + chapterIndex;
      }
      globalIndex += chapterData.pages.pages.length;
    }
    return -1;
  }

  /// Return the ``ChapterPagesDto`` for [currentChapter] within the
  /// loaded set, falling back to [fallbackChapterPages] if not loaded.
  static ChapterPagesDto createChapterPagesDto(
    List<({ChapterPagesDto pages, ChapterDto chapter, int chapterId})>
        loadedChapters,
    ChapterDto currentChapter,
    ChapterPagesDto fallbackChapterPages,
  ) {
    for (final chapterData in loadedChapters) {
      if (chapterData.chapterId == currentChapter.id) {
        return chapterData.pages;
      }
    }
    return fallbackChapterPages;
  }
}
