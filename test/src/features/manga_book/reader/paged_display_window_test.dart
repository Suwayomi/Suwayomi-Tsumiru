// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_mode/paged_display_window.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_mode/paged_spread_mapping.dart';

/// Build a loaded chapter with [pageCount] pages, page URLs like `cID-pN`.
WindowChapter chapter(
  int id, {
  required int pageCount,
  bool doublePages = false,
  bool hasGapBefore = false,
}) {
  return WindowChapter(
    chapterId: id,
    chapterName: 'Chapter $id',
    mapping: buildSpreadMapping(
      pageCount: pageCount,
      doublePages: doublePages,
      splitWide: false,
      splitInvert: false,
      isWide: (_) => false,
    ),
    pages: [for (var i = 0; i < pageCount; i++) 'c$id-p$i'],
    hasGapBefore: hasGapBefore,
  );
}

/// Compact description of each display slot: "cID:raw" for a spread's primary
/// raw, or "T(from>to)" for a transition.
List<String> shape(PagedDisplayWindow w) => [
      for (final item in w.items)
        switch (item) {
          SpreadDisplay(:final chapterId, :final entry) =>
            'c$chapterId:${entry.primaryRaw}',
          TransitionDisplay(:final fromChapterId, :final toChapterId) =>
            'T($fromChapterId>$toChapterId)',
        },
    ];

void main() {
  group('single chapter — no transitions', () {
    test('spreads only, addressing round-trips', () {
      final w = buildPagedDisplayWindow(
        chapters: [chapter(7, pageCount: 3)],
        forceTransition: false,
      );
      expect(w.length, 3);
      expect(shape(w), ['c7:0', 'c7:1', 'c7:2']);
      for (var raw = 0; raw < 3; raw++) {
        expect(w.chapterRawToDisplay(7, raw), raw);
        expect(w.displayToChapterRaw(raw), (chapterId: 7, raw: raw));
      }
      expect(w.firstDisplayOf(7), 0);
      expect(w.pagesAt(1), ['c7-p0', 'c7-p1', 'c7-p2']);
    });

    test('empty window', () {
      final w = buildPagedDisplayWindow(chapters: [], forceTransition: false);
      expect(w.isEmpty, isTrue);
      expect(w.displayToChapterRaw(0), isNull);
      expect(w.chapterRawToDisplay(1, 0), -1);
    });
  });

  group('two chapters', () {
    test('seamless: no transition between loaded chapters', () {
      final w = buildPagedDisplayWindow(
        chapters: [chapter(1, pageCount: 2), chapter(2, pageCount: 2)],
        forceTransition: false,
      );
      // Last spread of ch1 sits directly before the first of ch2.
      expect(shape(w), ['c1:0', 'c1:1', 'c2:0', 'c2:1']);
      expect(w.displayToChapterRaw(1), (chapterId: 1, raw: 1));
      expect(w.displayToChapterRaw(2), (chapterId: 2, raw: 0));
      expect(w.chapterRawToDisplay(2, 0), 2);
      expect(w.firstDisplayOf(2), 2);
    });

    test('forceTransition inserts a boundary card between them', () {
      final w = buildPagedDisplayWindow(
        chapters: [chapter(1, pageCount: 2), chapter(2, pageCount: 2)],
        forceTransition: true,
      );
      expect(shape(w), ['c1:0', 'c1:1', 'T(1>2)', 'c2:0', 'c2:1']);
      // The transition slot has no page mapping.
      expect(w.displayToChapterRaw(2), isNull);
      expect(w.displayToChapterProgressRaw(2), isNull);
      expect(w.pagesAt(2), isNull);
      // Chapter 2's pages start after the transition.
      expect(w.firstDisplayOf(2), 3);
      expect(w.chapterRawToDisplay(2, 1), 4);
    });

    test('hasGapBefore forces a transition even when seamless', () {
      final w = buildPagedDisplayWindow(
        chapters: [
          chapter(1, pageCount: 1),
          chapter(5, pageCount: 1, hasGapBefore: true),
        ],
        forceTransition: false,
      );
      expect(shape(w), ['c1:0', 'T(1>5)', 'c5:0']);
    });
  });

  group('leading / trailing edge transitions', () {
    test('leading and trailing boundary cards wrap the window', () {
      final w = buildPagedDisplayWindow(
        chapters: [chapter(3, pageCount: 2)],
        forceTransition: false,
        leadingTransition: true,
        trailingTransition: true,
      );
      expect(shape(w), ['T(null>3)', 'c3:0', 'c3:1', 'T(3>null)']);
      final lead = w.items.first as TransitionDisplay;
      final tail = w.items.last as TransitionDisplay;
      expect(lead.isStart, isTrue);
      expect(tail.isEnd, isTrue);
      // Chapter pages are offset by the leading card.
      expect(w.firstDisplayOf(3), 1);
      expect(w.chapterRawToDisplay(3, 1), 2);
      expect(w.displayToChapterRaw(0), isNull); // leading transition
    });
  });

  group('double-page across chapters', () {
    test('progress raw is the furthest page of each spread, per chapter', () {
      final w = buildPagedDisplayWindow(
        chapters: [
          chapter(1, pageCount: 4, doublePages: true), // (0,1)(2,3)
          chapter(2, pageCount: 4, doublePages: true), // (0,1)(2,3)
        ],
        forceTransition: false,
      );
      // 2 spreads per chapter, seamless.
      expect(shape(w), ['c1:0', 'c1:2', 'c2:0', 'c2:2']);
      // Seekbar (primary) vs progress (furthest) raw.
      expect(w.displayToChapterRaw(1), (chapterId: 1, raw: 2));
      expect(w.displayToChapterProgressRaw(1), (chapterId: 1, raw: 3));
      // Second page of a pair maps to that pair.
      expect(w.chapterRawToDisplay(1, 3), 1);
      expect(w.chapterRawToDisplay(2, 1), 2);
      // Last spread of ch2 reports ch2's last page for progress → can mark read.
      expect(w.displayToChapterProgressRaw(3), (chapterId: 2, raw: 3));
    });
  });

  group('lookups for absent content', () {
    test('chapterRawToDisplay returns -1 for a chapter not in the window', () {
      final w = buildPagedDisplayWindow(
        chapters: [chapter(1, pageCount: 2)],
        forceTransition: false,
      );
      expect(w.chapterRawToDisplay(99, 0), -1);
      expect(w.firstDisplayOf(99), -1);
    });

    test('out-of-range display indexes never throw', () {
      final w = buildPagedDisplayWindow(
        chapters: [chapter(1, pageCount: 2)],
        forceTransition: false,
      );
      expect(w.displayToChapterRaw(-1), isNull);
      expect(w.displayToChapterRaw(999), isNull);
      expect(w.pagesAt(999), isNull);
    });
  });
}
