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

void main() {
  const axis = Axis.horizontal;
  const reverse = false;
  const doublePages = false;
  const boundary = 'interior';

  testWidgets('a window update preserves the transition card', (tester) async {
    final dir = Directory.systemTemp.createTempSync('paged-gap-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final page = File('${dir.path}/page.png')
      ..writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=',
        ),
      );
    WindowChapter chapter(int id, {bool gap = false, bool wide = false}) =>
        WindowChapter(
          chapterId: id,
          chapterName: 'Chapter $id',
          hasGapBefore: gap,
          mapping: buildSpreadMapping(
            pageCount: 4,
            doublePages: doublePages,
            splitWide: false,
            splitInvert: false,
            isWide: (raw) => wide && raw == 0,
          ),
          pages: List.filled(4, page.uri.toString()),
        );
    final oldWindow = buildPagedDisplayWindow(
      chapters: boundary == 'interior' || boundary == 'removed'
          ? [chapter(1), chapter(5, gap: true)]
          : [chapter(boundary == 'prepend' ? 5 : 1)],
      forceTransition: false,
      leadingTransition: boundary == 'prepend',
      trailingTransition: boundary == 'append' || boundary == 'seamless',
    );
    final initial = oldWindow.items.indexWhere(
      (item) => item is TransitionDisplay,
    );
    final controller = PagedReaderController();
    final progress = <(int, int)>[];
    Future<void> pump(PagedDisplayWindow window) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 600,
              height: 500,
              child: PagedReaderViewport(
                controller: controller,
                window: window,
                initialDisplayIndex: initial,
                axis: axis,
                reverse: reverse,
                animateTransitions: false,
                pageFit: BoxFit.contain,
                pageSize: null,
                pagesAtNaturalSize: false,
                mouseScrollSpeed: 1,
                centerMargin: CenterMarginType.none,
                rotateWide: false,
                rotateWideInvert: false,
                reversePair: false,
                offsetDoublePages: false,
                cropBorders: false,
                onPageWide: (_, _, _) {},
                onChapterPageChanged: (id, raw) => progress.add((id, raw)),
                transitionBuilder: (_) => const Center(
                  child: Text('Missing chapters', key: Key('gap-card')),
                ),
                pinchEnabled: false,
                doubleTapToZoom: false,
                disableZoomIn: false,
                disableZoomOut: false,
                navigateToPan: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pump(oldWindow);
    expect(progress, isEmpty);

    // Loading a neighbour turns an edge card into an interior card.
    // A wide-page discovery also changes spread indexes in dual mode.
    final newWindow = buildPagedDisplayWindow(
      chapters: [
        chapter(1, wide: true),
        chapter(5, gap: boundary != 'removed' && boundary != 'seamless'),
      ],
      forceTransition: false,
    );
    await pump(newWindow);
    if (boundary == 'removed' || boundary == 'seamless') {
      // Existing fallback behavior is unchanged when there is no card
      // left to preserve: interior -> entered chapter, end -> last page.
      expect(progress.last, (1, 3));
      expect(find.byKey(const Key('gap-card')), findsNothing);
      expect(tester.takeException(), isNull);
      return;
    }
    expect(
      progress,
      isEmpty,
      reason: 'a rebuild must not advance into a chapter',
    );
    final card = find.byKey(const Key('gap-card'));
    expect(card, findsOneWidget);
    expect(tester.getCenter(card).dx, closeTo(400, 1));
    expect(tester.getCenter(card).dy, closeTo(300, 1));

    // The notice must remain at rest, not merely appear for one frame.
    await tester.pump(const Duration(seconds: 1));
    expect(progress, isEmpty);

    await pump(
      buildPagedDisplayWindow(
        chapters: [chapter(1), chapter(5, gap: true)],
        forceTransition: false,
      ),
    );
    expect(progress, isEmpty);

    controller.next();
    await tester.pumpAndSettle();
    expect(progress.last, (5, 0));
    expect(tester.takeException(), isNull);

    PagedDisplayWindow splitWindow({bool earlierWide = false}) =>
        buildPagedDisplayWindow(
          chapters: [
            WindowChapter(
              chapterId: 5,
              chapterName: 'Chapter 5',
              mapping: buildSpreadMapping(
                pageCount: 4,
                doublePages: false,
                splitWide: true,
                splitInvert: false,
                isWide: (raw) => raw == 1 || (earlierWide && raw == 0),
              ),
              pages: List.filled(4, page.uri.toString()),
            ),
          ],
          forceTransition: false,
        );

    await pump(splitWindow());
    controller.jumpToRaw(1);
    controller.next();
    await tester.pumpAndSettle();
    await pump(splitWindow(earlierWide: true));
    controller.next();
    await tester.pumpAndSettle();
    expect(progress.last, (5, 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('offset toggles keep the WebUI page and never drift', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('paged-offset-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final page = File('${dir.path}/page.png')
      ..writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=',
        ),
      );
    WindowChapter offsetChapter(bool offset) => WindowChapter(
      chapterId: 1,
      chapterName: 'Chapter 1',
      mapping: buildSpreadMapping(
        pageCount: 9,
        doublePages: true,
        splitWide: false,
        splitInvert: false,
        offsetDoublePages: offset,
        isWide: (_) => false,
      ),
      pages: List.filled(9, page.uri.toString()),
    );
    final controller = PagedReaderController();
    final progress = <(int, int)>[];
    Future<void> pump(bool offset) async {
      final window = buildPagedDisplayWindow(
        chapters: [offsetChapter(offset)],
        forceTransition: false,
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 600,
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
                pagesAtNaturalSize: false,
                mouseScrollSpeed: 1,
                centerMargin: CenterMarginType.none,
                rotateWide: false,
                rotateWideInvert: false,
                reversePair: false,
                offsetDoublePages: offset,
                cropBorders: false,
                onPageWide: (_, _, _) {},
                onChapterPageChanged: (id, raw) => progress.add((id, raw)),
                transitionBuilder: (_) => const SizedBox.shrink(),
                pinchEnabled: false,
                doubleTapToZoom: false,
                disableZoomIn: false,
                disableZoomOut: false,
                navigateToPan: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pump(false);
    controller.jumpToRaw(4);
    await tester.pumpAndSettle();
    // Slot (4,5) reports its furthest page.
    expect(progress.last, (1, 5));

    await pump(true);
    expect(progress.last, (1, 4));

    await pump(false);
    expect(progress.last, (1, 5));

    await pump(true);
    expect(progress.last, (1, 4));

    // The chapter's last spread reports its final page so the chapter is marked read.
    controller.jumpToRaw(7);
    await tester.pumpAndSettle();
    expect(progress.last, (1, 8));

    await pump(false);
    expect(progress.last, (1, 8));
    expect(tester.takeException(), isNull);
  });
}
