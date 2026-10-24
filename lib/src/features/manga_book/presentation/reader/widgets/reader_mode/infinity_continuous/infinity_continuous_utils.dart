// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../../../domain/chapter/chapter_model.dart';
import '../../../../../domain/chapter_page/chapter_page_model.dart';

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

  /// Selects the most visible page, except the last wins at the scrolled end; resting short chapters do not complete.
  static int? selectCurrentIndex(
    List<ItemPosition> positions,
    int total, {
    required double minVisibleAreaThreshold,
  }) {
    if (positions.isEmpty) return null;

    // Tolerate subpixel noise at rest so a short chapter does not mark read on open.
    const restEps = 0.0015;
    final firstPage = positions.where((p) => p.index == 0);
    final restingAtTop =
        firstPage.isNotEmpty && firstPage.first.itemLeadingEdge >= -restEps;

    // The end card shares the last item; tolerate float noise when testing its bottom edge.
    final lastPage = positions.where((p) => p.index == total - 1);
    if (total > 1 &&
        !restingAtTop &&
        lastPage.isNotEmpty &&
        lastPage.first.itemTrailingEdge <= 1.0 + restEps) {
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

  static int getTotalPages(
    List<({ChapterPagesDto pages, ChapterDto chapter, int chapterId})>
        loadedChapters,
  ) {
    return loadedChapters.fold(
      0,
      (sum, chapterData) => sum + chapterData.pages.pages.length,
    );
  }

  /// Chapter edges with a loaded neighbour, used for separators.
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

  /// Returns the global page index, or -1 if the chapter is not loaded.
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
