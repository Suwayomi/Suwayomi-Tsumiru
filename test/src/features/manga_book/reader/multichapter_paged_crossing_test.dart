// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_mode/double_page_view.dart';
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

double _largestScale(WidgetTester tester) {
  var best = 1.0;
  for (final t in tester.widgetList<Transform>(find.byType(Transform))) {
    final s = t.transform.storage;
    final sx = math.sqrt(s[0] * s[0] + s[1] * s[1]);
    if (sx > best) best = sx;
  }
  return best;
}

/// The viewport the newer cases share. They differ only in their window, where
/// they start, and what they report.
Widget _viewport({
  required PagedReaderController controller,
  required PagedDisplayWindow window,
  int initialDisplayIndex = 0,
  void Function(int chapterId, int raw)? onChapterPageChanged,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: ReaderInputScope(
    callbacks: _callbacks(),
    child: Center(
      child: SizedBox(
        width: 300,
        height: 500,
        child: PagedReaderViewport(
          controller: controller,
          window: window,
          initialDisplayIndex: initialDisplayIndex,
          axis: Axis.horizontal,
          reverse: false,
          animateTransitions: true,
          pageFit: BoxFit.contain,
          pageSize: null,
          pagesAtNaturalSize: false,
          mouseScrollSpeed: 1.7,
          centerMargin: CenterMarginType.none,
          rotateWide: false,
          rotateWideInvert: false,
          reversePair: false,
          cropBorders: false,
          onPageWide: (_, __, ___) {},
          onChapterPageChanged: onChapterPageChanged ?? (_, __) {},
          transitionBuilder: (_) => const SizedBox.shrink(),
          pinchEnabled: true,
          doubleTapToZoom: true,
          disableZoomIn: false,
          disableZoomOut: false,
          navigateToPan: true,
        ),
      ),
    ),
  ),
);

/// Pages must sit a whole screen apart; a leftover offset parks the pager
/// between two, showing half of each.
void _expectPagesAligned(WidgetTester tester) {
  final box = tester.getRect(find.byType(PagedReaderViewport));
  final pages = find.byType(DoublePageView);
  expect(pages, findsWidgets);
  for (var i = 0; i < tester.widgetList(pages).length; i++) {
    final dx = tester.getTopLeft(pages.at(i)).dx - box.left;
    final steps = dx / box.width;
    final offBy = (steps - steps.roundToDouble()).abs() * box.width;
    expect(
      offBy,
      lessThan(1.0),
      reason: 'page $i parked between pages at dx=$dx',
    );
  }
}

void main() {
  testWidgets('double-tap zoom animates instead of snapping', (tester) async {
    final window = buildPagedDisplayWindow(
      chapters: [_chapter(1, 1)],
      forceTransition: false,
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ReaderInputScope(
          callbacks: _callbacks(),
          child: SizedBox(
            width: 300,
            height: 500,
            child: PagedReaderViewport(
              controller: PagedReaderController(),
              window: window,
              initialDisplayIndex: 0,
              axis: Axis.horizontal,
              reverse: false,
              animateTransitions: true,
              pageFit: BoxFit.contain,
              pageSize: null,
              pagesAtNaturalSize: false,
              mouseScrollSpeed: 1.7,
              centerMargin: CenterMarginType.none,
              rotateWide: false,
              rotateWideInvert: false,
              reversePair: false,
              cropBorders: false,
              onPageWide: (_, __, ___) {},
              onChapterPageChanged: (_, __) {},
              transitionBuilder: (_) => const SizedBox.shrink(),
              pinchEnabled: true,
              doubleTapToZoom: true,
              disableZoomIn: false,
              disableZoomOut: false,
              navigateToPan: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final center = tester.getCenter(find.byType(PagedReaderViewport));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(center); // second tap → double-tap-to-zoom
    // Part-way through the 200ms zoom: scaled up, but not yet at the 2x target.
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 90));
    final mid = _largestScale(tester);
    expect(mid, greaterThan(1.02), reason: 'zoom did not start ($mid)');
    expect(mid, lessThan(1.98), reason: 'zoom snapped instantly ($mid)');

    await tester.pumpAndSettle();
    expect(_largestScale(tester), closeTo(2.0, 0.05));
  });

  testWidgets('paging crosses from chapter 1 into chapter 2 in one window', (
    tester,
  ) async {
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
          pagesAtNaturalSize: false,
          mouseScrollSpeed: 1.7,
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
    expect(
      reported.any((e) => e.chapterId == 2),
      isTrue,
      reason: 'paging never crossed into chapter 2; reported=$reported',
    );
    // And landed on chapter 2's last page.
    expect(reported.last, (chapterId: 2, raw: 2));
  });

  testWidgets('a window swap while on a boundary card does not jump to start', (
    tester,
  ) async {
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
          pagesAtNaturalSize: false,
          mouseScrollSpeed: 1.7,
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
      Directionality(
        textDirection: TextDirection.ltr,
        child: viewportWith(window1),
      ),
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
      Directionality(
        textDirection: TextDirection.ltr,
        child: viewportWith(window2),
      ),
    );
    await tester.pumpAndSettle();

    // The re-anchor must keep us at the boundary (end of ch1 / start of ch2),
    // NOT throw us back to chapter 1 page 0.
    expect(reported.isNotEmpty, isTrue);
    expect(
      reported.last,
      isNot((chapterId: 1, raw: 0)),
      reason: 're-anchor jumped to the start; reported=$reported',
    );
  });

  testWidgets('a chapter loading mid page-turn keeps the page you were on', (
    tester,
  ) async {
    final reported = <({int chapterId, int raw})>[];
    final controller = PagedReaderController();

    Widget viewportWith(PagedDisplayWindow window) => ReaderInputScope(
      callbacks: _callbacks(),
      child: Center(
        child: SizedBox(
          width: 300,
          height: 500,
          child: PagedReaderViewport(
            controller: controller,
            window: window,
            initialDisplayIndex: 0,
            axis: Axis.horizontal,
            reverse: false,
            animateTransitions: true,
            pageFit: BoxFit.contain,
            pageSize: null,
            pagesAtNaturalSize: false,
            mouseScrollSpeed: 1.7,
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
      ),
    );

    // Reading chapter 2 alone; chapter 1 loads in behind us, which shifts every
    // display index by a chapter.
    final window1 = buildPagedDisplayWindow(
      chapters: [_chapter(2, 3)],
      forceTransition: false,
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: viewportWith(window1),
      ),
    );
    await tester.pump();

    // Turn a page and swap the window while that turn is still settling.
    await tester.timedDrag(
      find.byType(PagedReaderViewport),
      const Offset(-90, 0),
      const Duration(milliseconds: 80),
    );
    await tester.pump(const Duration(milliseconds: 30));

    reported.clear();
    final window2 = buildPagedDisplayWindow(
      chapters: [_chapter(1, 3), _chapter(2, 3)],
      forceTransition: false,
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: viewportWith(window2),
      ),
    );
    await tester.pumpAndSettle();

    // The in-flight turn was aimed at the old window; committing it now would
    // land on whatever chapter 1 page happens to share that index.
    expect(reported.isNotEmpty, isTrue);
    expect(
      reported.last.chapterId,
      2,
      reason: 'landed outside the chapter being read; reported=$reported',
    );
  });

  testWidgets('jumping while a page turn is still settling lands on the jump', (
    tester,
  ) async {
    final reported = <({int chapterId, int raw})>[];
    final controller = PagedReaderController();

    final window = buildPagedDisplayWindow(
      chapters: [_chapter(1, 6)],
      forceTransition: false,
    );

    await tester.pumpWidget(
      _viewport(
        controller: controller,
        window: window,
        onChapterPageChanged: (chapterId, raw) =>
            reported.add((chapterId: chapterId, raw: raw)),
      ),
    );
    await tester.pump();

    // Turn a page, then jump the seekbar elsewhere before the turn settles.
    await tester.timedDrag(
      find.byType(PagedReaderViewport),
      const Offset(-90, 0),
      const Duration(milliseconds: 80),
    );
    await tester.pump(const Duration(milliseconds: 30));

    reported.clear();
    controller.jumpToRaw(5);
    await tester.pumpAndSettle();

    // The abandoned turn must not commit page 1 on top of the jump.
    expect(reported.isNotEmpty, isTrue);
    expect(
      reported.last.raw,
      5,
      reason: 'the in-flight turn overrode the jump; reported=$reported',
    );
  });

  testWidgets('a drag that follows a pinch still settles when you let go', (
    tester,
  ) async {
    final controller = PagedReaderController();
    final window = buildPagedDisplayWindow(
      chapters: [_chapter(1, 6)],
      forceTransition: false,
    );

    await tester.pumpWidget(
      _viewport(controller: controller, window: window, initialDisplayIndex: 1),
    );
    await tester.pump();

    final box = tester.getRect(find.byType(PagedReaderViewport));
    final a = box.center - const Offset(30, 0);
    final b = box.center + const Offset(30, 0);

    // Pinch, drop to one finger, then drag that finger to turn the page.
    final p1 = await tester.startGesture(a, pointer: 1);
    final p2 = await tester.startGesture(b, pointer: 2);
    await tester.pump();
    // Both fingers together: engages multi-touch without changing the scale,
    // so the assertion below measures position rather than zoom.
    await p1.moveTo(a + const Offset(10, 0));
    await p2.moveTo(b + const Offset(10, 0));
    await tester.pump();
    await p2.up(); // back to one finger, still "multi-touch" internally
    await tester.pump();

    for (var i = 0; i < 6; i++) {
      await p1.moveBy(const Offset(-25, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await p1.up();
    await tester.pumpAndSettle();

    // Releasing must land on a page; unsettled it stays frozen where the
    // finger stopped, showing two pages at once.
    _expectPagesAligned(tester);
  });

  testWidgets('a second finger mid-turn cannot hijack the turn into a zoom', (
    tester,
  ) async {
    final controller = PagedReaderController();
    final window = buildPagedDisplayWindow(
      chapters: [_chapter(1, 6)],
      forceTransition: false,
    );

    await tester.pumpWidget(
      _viewport(controller: controller, window: window, initialDisplayIndex: 1),
    );
    await tester.pump();

    final box = tester.getRect(find.byType(PagedReaderViewport));

    // Begin a page turn with one finger...
    final p1 = await tester.startGesture(box.center, pointer: 1);
    for (var i = 0; i < 4; i++) {
      await p1.moveBy(const Offset(-20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }

    // ...then drop a second finger and spread, as if pinching to zoom.
    final p2 = await tester.startGesture(
      box.center + const Offset(40, 0),
      pointer: 2,
    );
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await p2.moveBy(const Offset(25, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }

    // Komikku doesn't zoom while a page is turning, and neither do we.
    expect(
      _largestScale(tester),
      closeTo(1.0, 0.01),
      reason: 'the pinch hijacked a turn in progress',
    );

    await p2.up();
    await p1.up();
    await tester.pumpAndSettle();

    // And the turn still lands on a page.
    _expectPagesAligned(tester);
  });

  testWidgets('a cancelled finger does not leave a tap behind', (tester) async {
    var taps = 0;
    final controller = PagedReaderController();
    final window = buildPagedDisplayWindow(
      chapters: [_chapter(1, 6)],
      forceTransition: false,
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ReaderInputScope(
          callbacks: ReaderInputCallbacks(
            onTap: () => taps++,
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
          ),
          child: Center(
            child: SizedBox(
              width: 300,
              height: 500,
              child: PagedReaderViewport(
                controller: controller,
                window: window,
                initialDisplayIndex: 1,
                axis: Axis.horizontal,
                reverse: false,
                animateTransitions: true,
                pageFit: BoxFit.contain,
                pageSize: null,
                pagesAtNaturalSize: false,
                mouseScrollSpeed: 1.7,
                centerMargin: CenterMarginType.none,
                rotateWide: false,
                rotateWideInvert: false,
                reversePair: false,
                cropBorders: false,
                onPageWide: (_, __, ___) {},
                onChapterPageChanged: (_, __) {},
                transitionBuilder: (_) => const SizedBox.shrink(),
                pinchEnabled: true,
                doubleTapToZoom: true,
                disableZoomIn: false,
                disableZoomOut: false,
                navigateToPan: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final box = tester.getRect(find.byType(PagedReaderViewport));

    // Two fingers down, one cancelled, then the other lifts without moving.
    // The survivor must not be read as a fresh tap.
    final p1 = await tester.startGesture(box.center, pointer: 1);
    final p2 = await tester.startGesture(
      box.center + const Offset(40, 0),
      pointer: 2,
    );
    await tester.pump();
    await p2.cancel();
    await tester.pump();
    await p1.up();
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    expect(taps, 0, reason: 'a cancelled gesture fired a tap');
    _expectPagesAligned(tester);
  });

  testWidgets('the wheel pans a zoomed page before turning it', (tester) async {
    final reported = <({int chapterId, int raw})>[];
    final controller = PagedReaderController();
    final window = buildPagedDisplayWindow(
      chapters: [_chapter(1, 6)],
      forceTransition: false,
    );

    await tester.pumpWidget(
      _viewport(
        controller: controller,
        window: window,
        onChapterPageChanged: (chapterId, raw) =>
            reported.add((chapterId: chapterId, raw: raw)),
      ),
    );
    await tester.pump();

    final box = tester.getRect(find.byType(PagedReaderViewport));
    // Zoom in so the page has somewhere to pan to.
    await tester.tapAt(box.center);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(box.center);
    await tester.pumpAndSettle();

    double scaleOffset() {
      for (final t in tester.widgetList<Transform>(find.byType(Transform))) {
        final m = t.transform.storage;
        if ((m[0] - 1).abs() < 0.001 && m[13].abs() > 0.001) return m[13];
      }
      return 0;
    }

    final before = scaleOffset();
    reported.clear();

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(box.center);
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 53)));
    await tester.pumpAndSettle();

    expect(
      scaleOffset(),
      isNot(closeTo(before, 0.001)),
      reason: 'the wheel did not pan the zoomed page',
    );
    expect(
      reported,
      isEmpty,
      reason: 'the wheel turned the page while it still had room to pan',
    );
  });

  testWidgets('the wheel turns a page that has nowhere to pan', (tester) async {
    final reported = <({int chapterId, int raw})>[];
    final controller = PagedReaderController();
    final window = buildPagedDisplayWindow(
      chapters: [_chapter(1, 6)],
      forceTransition: false,
    );

    await tester.pumpWidget(
      _viewport(
        controller: controller,
        window: window,
        onChapterPageChanged: (chapterId, raw) =>
            reported.add((chapterId: chapterId, raw: raw)),
      ),
    );
    await tester.pump();
    reported.clear();

    // Not zoomed: a fitted page has no room, so the notch turns it.
    final box = tester.getRect(find.byType(PagedReaderViewport));
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(box.center);
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 53)));
    await tester.pumpAndSettle();

    expect(
      reported.map((r) => r.raw),
      contains(1),
      reason: 'the wheel did not turn a page it could not pan',
    );
  });
}
