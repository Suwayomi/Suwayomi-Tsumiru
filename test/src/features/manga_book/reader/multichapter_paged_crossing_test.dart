// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_mode/paged_display_window.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_mode/paged_reader_viewport.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_mode/paged_spread_mapping.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_wrapper.dart';

const _png1x1 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=';

List<String> _localPages(int count, String tag) {
  final dir = Directory.systemTemp.createTempSync('tsumiru-mc-$tag-');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  final bytes = base64Decode(_png1x1);
  return [
    for (var i = 0; i < count; i++)
      (File('${dir.path}/$i.png')..writeAsBytesSync(bytes)).uri.toString(),
  ];
}

WindowChapter _chapter(int id, int pageCount) => WindowChapter(
      chapterId: id,
      chapterName: 'Chapter $id',
      mapping: buildSpreadMapping(
        pageCount: pageCount,
        doublePages: false,
        splitWide: false,
        splitInvert: false,
        isWide: (_) => false,
      ),
      pages: _localPages(pageCount, 'c$id'),
    );

ReaderInputCallbacks _callbacks() => ReaderInputCallbacks(
      onTap: () {},
      onLongPressStart: (_) {},
      onLongPressMoveUpdate: (_) {},
      onLongPressEnd: () {},
      onLongPressCancel: () {},
      onNext: () {},
      onPrevious: () {},
      onNextBoundary: () => false,
      onPreviousBoundary: () => false,
      navigationLayout: ReaderNavigationLayout.disabled,
      tapInvert: TapInvert.none,
      smallerTapZones: false,
    );

void main() {
  testWidgets('paging crosses from chapter 1 into chapter 2 in one window',
      (tester) async {
    // Both chapters already loaded, seamless (no transition between them).
    final window = buildPagedDisplayWindow(
      chapters: [_chapter(1, 3), _chapter(2, 3)],
      forceTransition: false,
    );
    // items: c1:0 c1:1 c1:2 c2:0 c2:1 c2:2  (6 slots)
    expect(window.length, 6);

    final reported = <({int chapterId, int raw})>[];
    final controller = PagedReaderController();

    final viewport = ReaderInputScope(
      callbacks: _callbacks(),
      child: SizedBox(
        width: 300,
        height: 500,
        child: PagedReaderViewport(
          controller: controller,
          window: window,
          initialDisplayIndex: 0,
          axis: Axis.horizontal,
          reverse: false,
          animateTransitions: false,
          pageFit: BoxFit.contain,
          pageSize: null,
          centerMargin: CenterMarginType.none,
          rotateWide: false,
          rotateWideInvert: false,
          reversePair: false,
          cropBorders: false,
          onPageWide: (_, __, ___) {},
          onChapterPageChanged: (chapterId, raw) =>
              reported.add((chapterId: chapterId, raw: raw)),
          transitionBuilder: (_) => const SizedBox.shrink(),
          pinchEnabled: true,
          doubleTapToZoom: true,
          disableZoomIn: false,
          disableZoomOut: false,
          navigateToPan: true,
        ),
      ),
    );
    await tester.pumpWidget(
      Directionality(textDirection: TextDirection.ltr, child: viewport),
    );
    await tester.pump();

    // Fling forward five times: c1:0 -> c1:1 -> c1:2 -> c2:0 -> c2:1 -> c2:2.
    for (var i = 0; i < 5; i++) {
      await tester.timedDrag(
        find.byType(PagedReaderViewport),
        const Offset(-90, 0),
        const Duration(milliseconds: 80),
      );
      await tester.pumpAndSettle();
    }

    // We must have crossed into chapter 2.
    expect(reported.any((e) => e.chapterId == 2), isTrue,
        reason: 'paging never crossed into chapter 2; reported=$reported');
    // And landed on chapter 2's last page.
    expect(reported.last, (chapterId: 2, raw: 2));
  });

  testWidgets('a window swap while on a boundary card does not jump to start',
      (tester) async {
    final reported = <({int chapterId, int raw})>[];
    final controller = PagedReaderController();

    Widget viewportWith(PagedDisplayWindow window) => ReaderInputScope(
          callbacks: _callbacks(),
          child: SizedBox(
            width: 300,
            height: 500,
            child: PagedReaderViewport(
              controller: controller,
              window: window,
              initialDisplayIndex: 0,
              axis: Axis.horizontal,
              reverse: false,
              animateTransitions: false,
              pageFit: BoxFit.contain,
              pageSize: null,
              centerMargin: CenterMarginType.none,
              rotateWide: false,
              rotateWideInvert: false,
              reversePair: false,
              cropBorders: false,
              onPageWide: (_, __, ___) {},
              onChapterPageChanged: (chapterId, raw) =>
                  reported.add((chapterId: chapterId, raw: raw)),
              transitionBuilder: (_) => const SizedBox.shrink(),
              pinchEnabled: true,
              doubleTapToZoom: true,
              disableZoomIn: false,
              disableZoomOut: false,
              navigateToPan: true,
            ),
          ),
        );

    // Only chapter 1 loaded, with a trailing "next chapter" card at the edge.
    final window1 = buildPagedDisplayWindow(
      chapters: [_chapter(1, 2)],
      forceTransition: false,
      trailingTransition: true,
    );
    // items: c1:0 c1:1 T(end)  (3 slots)
    await tester.pumpWidget(
      Directionality(textDirection: TextDirection.ltr, child: viewportWith(window1)),
    );
    await tester.pump();

    // Page forward onto the last real page, then onto the trailing card.
    for (var i = 0; i < 2; i++) {
      await tester.timedDrag(
        find.byType(PagedReaderViewport),
        const Offset(-90, 0),
        const Duration(milliseconds: 80),
      );
      await tester.pumpAndSettle();
    }

    // Now chapter 2 loads in — swap the window.
    final window2 = buildPagedDisplayWindow(
      chapters: [_chapter(1, 2), _chapter(2, 2)],
      forceTransition: false,
    );
    reported.clear();
    await tester.pumpWidget(
      Directionality(textDirection: TextDirection.ltr, child: viewportWith(window2)),
    );
    await tester.pumpAndSettle();

    // The re-anchor must keep us at the boundary (end of ch1 / start of ch2),
    // NOT throw us back to chapter 1 page 0.
    expect(reported.isNotEmpty, isTrue);
    expect(reported.last, isNot((chapterId: 1, raw: 0)),
        reason: 're-anchor jumped to the start; reported=$reported');
  });
}
