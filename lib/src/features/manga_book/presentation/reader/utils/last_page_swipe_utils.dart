// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import '../../../../../constants/enum.dart';
import '../../../domain/chapter_page/chapter_page_model.dart';

enum SwipeDirection {
  left,
  right,
  up,
  down,
}

enum NavigationAction {
  pageNavigation,
  nextChapter,
  previousChapter,
}

enum PagePosition {
  firstPage,
  middlePage,
  lastPage,
  singlePage,
}

class LastPageSwipeUtils {
  LastPageSwipeUtils._();

  static SwipeDirection getExpectedSwipeDirection(ReaderMode mode) {
    switch (mode) {
      case ReaderMode.singleHorizontalLTR:
      case ReaderMode.continuousHorizontalLTR:
        return SwipeDirection.left;
      case ReaderMode.singleHorizontalRTL:
      case ReaderMode.continuousHorizontalRTL:
        return SwipeDirection.right;
      case ReaderMode.singleVertical:
      case ReaderMode.continuousVertical:
      case ReaderMode.webtoon:
        return SwipeDirection.up;
      case ReaderMode.defaultReader:
        return SwipeDirection.left;
    }
  }

  static ReaderMode resolveActualReaderMode({
    required ReaderMode? mangaReaderMode,
    required ReaderMode? defaultReaderMode,
  }) {
    if (mangaReaderMode == null ||
        mangaReaderMode == ReaderMode.defaultReader) {
      return defaultReaderMode ?? ReaderMode.webtoon;
    }
    return mangaReaderMode;
  }

  static bool isCorrectDirection(SwipeDirection actual, ReaderMode mode) {
    final expected = getExpectedSwipeDirection(mode);
    return actual == expected;
  }

  static SwipeDirection? detectSwipeDirection(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond;
    final primaryVelocity = details.primaryVelocity;

    if (primaryVelocity == null) return null;

    if (velocity.dx.abs() > velocity.dy.abs()) {
      return primaryVelocity > 0 ? SwipeDirection.right : SwipeDirection.left;
    }
    return primaryVelocity > 0 ? SwipeDirection.down : SwipeDirection.up;
  }

  static bool isAtLastPage({
    required int currentIndex,
    required ChapterPagesDto chapterPages,
  }) {
    if (chapterPages.pages.isEmpty) return false;
    return currentIndex >= chapterPages.pages.length - 1;
  }

  static bool isAtFirstPage({
    required int currentIndex,
  }) {
    return currentIndex <= 0;
  }

  static bool isAtLastPageByMetadata({
    required int currentIndex,
    required ChapterPagesDto chapterPages,
  }) {
    final pageCount = chapterPages.chapter.pageCount;
    if (pageCount <= 0) return false;
    return currentIndex >= (pageCount - 1);
  }

  static bool isAtLastPageReliable({
    required int currentIndex,
    required ChapterPagesDto chapterPages,
  }) {
    if (chapterPages.pages.isNotEmpty) {
      return isAtLastPage(
        currentIndex: currentIndex,
        chapterPages: chapterPages,
      );
    }
    return isAtLastPageByMetadata(
      currentIndex: currentIndex,
      chapterPages: chapterPages,
    );
  }

  static PagePosition detectPagePosition({
    required int currentIndex,
    required ChapterPagesDto chapterPages,
  }) {
    final isFirst = isAtFirstPage(currentIndex: currentIndex);
    final isLast = isAtLastPageReliable(
      currentIndex: currentIndex,
      chapterPages: chapterPages,
    );

    if (isFirst && isLast) {
      return PagePosition.singlePage;
    } else if (isFirst) {
      return PagePosition.firstPage;
    } else if (isLast) {
      return PagePosition.lastPage;
    } else {
      return PagePosition.middlePage;
    }
  }
}
