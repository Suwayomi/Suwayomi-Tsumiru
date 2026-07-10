// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_mode/paged_display_window.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_mode/paged_reader_viewport.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_mode/paged_spread_mapping.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_wrapper.dart';

const _png1x1 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=';

List<String> _localPages(int count) {
  final dir = Directory.systemTemp.createTempSync('tsumiru-paged-reader-');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  final bytes = base64Decode(_png1x1);
  return [
    for (var i = 0; i < count; i++)
      (File('${dir.path}/$i.png')..writeAsBytesSync(bytes)).uri.toString(),
  ];
}

ReaderInputCallbacks _callbacks({
  VoidCallback? onTap,
  bool Function()? onNextBoundary,
  bool Function()? onPreviousBoundary,
  bool Function()? hasNextBoundary,
  bool Function()? hasPreviousBoundary,
  ValueChanged<Offset>? onLongPressStart,
  VoidCallback? onLongPressEnd,
  VoidCallback? onLongPressCancel,
}) =>
    ReaderInputCallbacks(
      onTap: onTap ?? () {},
      onLongPressStart: onLongPressStart ?? (_) {},
      onLongPressMoveUpdate: (_) {},
      onLongPressEnd: onLongPressEnd ?? () {},
      onLongPressCancel: onLongPressCancel ?? () {},
      onNext: () {},
      onPrevious: () {},
      onNextBoundary: onNextBoundary ?? () => false,
      onPreviousBoundary: onPreviousBoundary ?? () => false,
      // Default to "a chapter exists" so boundary-move tests fire; the
      // no-adjacent-chapter case passes () => false explicitly.
      hasNextBoundary: hasNextBoundary ?? () => true,
      hasPreviousBoundary: hasPreviousBoundary ?? () => true,
      navigationLayout: ReaderNavigationLayout.disabled,
      tapInvert: TapInvert.none,
      smallerTapZones: false,
    );

Future<void> _pumpViewport(
  WidgetTester tester, {
  required PagedReaderController controller,
  required SpreadMapping mapping,
  required List<String> pages,
  required int initialDisplayIndex,
  required ValueChanged<int> onRawPageChanged,
  required ReaderInputCallbacks callbacks,
  Widget Function(Widget child)? wrapper,
  bool disableZoomOut = false,
  bool reverse = false,
  bool animateTransitions = false,
  Widget? previousBoundary,
  Widget? nextBoundary,
  VoidCallback? onReachedStartEdge,
  VoidCallback? onReachedEndEdge,
  void Function(int chapterId, int raw, bool isWide)? onPageWide,
}) async {
  // The viewport now renders a PagedDisplayWindow instead of a bare
  // mapping+pages pair. These single-chapter tests wrap the mapping in a
  // one-chapter window; a leading/trailing transition card stands in for the
  // old previousBoundary/nextBoundary widgets (rendered via transitionBuilder).
  final window = buildPagedDisplayWindow(
    chapters: [
      WindowChapter(
        chapterId: 1,
        chapterName: 'c1',
        mapping: mapping,
        pages: pages,
      ),
    ],
    forceTransition: false,
    leadingTransition: previousBoundary != null,
    trailingTransition: nextBoundary != null,
  );
  final viewport = ReaderInputScope(
    callbacks: callbacks,
    child: SizedBox(
      width: 300,
      height: 500,
      child: PagedReaderViewport(
        controller: controller,
        window: window,
        initialDisplayIndex: initialDisplayIndex,
        axis: Axis.horizontal,
        reverse: reverse,
        animateTransitions: animateTransitions,
        pageFit: BoxFit.contain,
        pageSize: null,
        centerMargin: CenterMarginType.none,
        rotateWide: false,
        rotateWideInvert: false,
        reversePair: false,
        cropBorders: false,
        onPageWide: onPageWide ?? (_, __, ___) {},
        onChapterPageChanged: (_, raw) => onRawPageChanged(raw),
        transitionBuilder: (transition) => transition.isStart
            ? (previousBoundary ?? const SizedBox.shrink())
            : (nextBoundary ?? const SizedBox.shrink()),
        pinchEnabled: true,
        doubleTapToZoom: true,
        disableZoomIn: false,
        disableZoomOut: disableZoomOut,
        navigateToPan: true,
        onReachedStartEdge: onReachedStartEdge,
        onReachedEndEdge: onReachedEndEdge,
      ),
    ),
  );
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: wrapper?.call(viewport) ?? viewport,
    ),
  );
  await tester.pump();
}

List<double> _transformScales(WidgetTester tester) => [
      for (final transform in tester.widgetList<Transform>(
        find.byType(Transform),
      ))
        _xyScale(transform.transform.storage),
    ];

double _xyScale(Float64List storage) {
  final scaleX = math.sqrt(storage[0] * storage[0] + storage[1] * storage[1]);
  final scaleY = math.sqrt(storage[4] * storage[4] + storage[5] * storage[5]);
  return math.max(scaleX, scaleY);
}

double _largestScale(WidgetTester tester) =>
    _transformScales(tester).reduce(math.max);

double _smallestScale(WidgetTester tester) =>
    _transformScales(tester).reduce(math.min);

List<Offset> _transformTranslations(WidgetTester tester) => [
      for (final transform in tester.widgetList<Transform>(
        find.byType(Transform),
      ))
        Offset(
          transform.transform.storage[12],
          transform.transform.storage[13],
        ),
    ];

double _leftmostTranslation(WidgetTester tester) =>
    _transformTranslations(tester).map((offset) => offset.dx).reduce(math.min);

Future<void> _doubleTapViewport(WidgetTester tester) async {
  final target = find.byType(PagedReaderViewport);
  await tester.tap(target);
  await tester.pump(const Duration(milliseconds: 80));
  await tester.tap(target);
  // Double-tap zoom now animates. A single pump only seeds the animation
  // controller's tick epoch (elapsed 0), so pump once to start it then settle
  // it to its target scale.
  await tester.pump();
  await tester.pumpAndSettle();
}

Future<void> _pinchViewportIn(WidgetTester tester) async {
  final center = tester.getCenter(find.byType(PagedReaderViewport));
  final first = await tester.startGesture(
    center - const Offset(80, 0),
    pointer: 1,
  );
  final second = await tester.startGesture(
    center + const Offset(80, 0),
    pointer: 2,
  );
  await tester.pump();

  await first.moveBy(const Offset(48, 0));
  await second.moveBy(const Offset(-48, 0));
  await tester.pump();

  await second.up();
  await first.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('command navigation reports raw page changes', (tester) async {
    final pages = _localPages(3);
    final mapping = buildSpreadMapping(
      pageCount: pages.length,
      doublePages: false,
      splitWide: false,
      splitInvert: false,
      isWide: (_) => false,
    );
    final controller = PagedReaderController();
    final reported = <int>[];

    await _pumpViewport(
      tester,
      controller: controller,
      mapping: mapping,
      pages: pages,
      initialDisplayIndex: 0,
      onRawPageChanged: reported.add,
      callbacks: _callbacks(),
    );
    reported.clear();

    controller.next();
    await tester.pumpAndSettle();

    expect(reported, [1]);
  });

  testWidgets('next command at the last display hits the end edge',
      (tester) async {
    // migrated: the viewport no longer performs the chapter move itself (that's
    // the host's job now). At the window's outer end it fires onReachedEndEdge —
    // the new edge signal that replaces the old onNextBoundary handoff.
    final pages = _localPages(3);
    final mapping = buildSpreadMapping(
      pageCount: pages.length,
      doublePages: false,
      splitWide: false,
      splitInvert: false,
      isWide: (_) => false,
    );
    final controller = PagedReaderController();
    var endEdgeHits = 0;

    await _pumpViewport(
      tester,
      controller: controller,
      mapping: mapping,
      pages: pages,
      initialDisplayIndex: 2,
      onRawPageChanged: (_) {},
      callbacks: _callbacks(),
      onReachedEndEdge: () => endEdgeHits += 1,
    );

    controller.next();
    await tester.pump();

    expect(endEdgeHits, 1);
  });

  testWidgets('next command lands on the chapter transition first',
      (tester) async {
    // migrated: the trailing transition card is now an ordinary in-window slot
    // (via transitionBuilder), so the first next() pages onto it and only the
    // next() past it reaches the window's end edge (onReachedEndEdge).
    final pages = _localPages(3);
    final mapping = buildSpreadMapping(
      pageCount: pages.length,
      doublePages: false,
      splitWide: false,
      splitInvert: false,
      isWide: (_) => false,
    );
    final controller = PagedReaderController();
    var endEdgeHits = 0;

    await _pumpViewport(
      tester,
      controller: controller,
      mapping: mapping,
      pages: pages,
      initialDisplayIndex: 2,
      onRawPageChanged: (_) {},
      callbacks: _callbacks(),
      onReachedEndEdge: () => endEdgeHits += 1,
      nextBoundary: const Text('Finished'),
    );

    expect(controller.isAtLast, isFalse);

    controller.next();
    await tester.pumpAndSettle();

    expect(find.text('Finished'), findsOneWidget);
    expect(controller.isAtLast, isTrue);
    expect(endEdgeHits, 0);

    controller.next();
    await tester.pumpAndSettle();

    expect(endEdgeHits, 1);
  });

  testWidgets('last display swipe hits the end edge', (tester) async {
    // migrated: a fling past the last page reaches the window's outer end, which
    // the viewport signals synchronously via onReachedEndEdge (then bounces).
    // The chapter move itself is now driven by the host off that signal.
    final pages = _localPages(3);
    final mapping = buildSpreadMapping(
      pageCount: pages.length,
      doublePages: false,
      splitWide: false,
      splitInvert: false,
      isWide: (_) => false,
    );
    final controller = PagedReaderController();
    var endEdgeHits = 0;

    await _pumpViewport(
      tester,
      controller: controller,
      mapping: mapping,
      pages: pages,
      initialDisplayIndex: 2,
      onRawPageChanged: (_) {},
      callbacks: _callbacks(),
      onReachedEndEdge: () => endEdgeHits += 1,
      animateTransitions: true,
    );

    await tester.timedDrag(
      find.byType(PagedReaderViewport),
      const Offset(-80, 0),
      const Duration(milliseconds: 80),
    );

    expect(endEdgeHits, 1);
    await tester.pumpAndSettle();
    expect(endEdgeHits, 1);
  });

  testWidgets('window end edge bounces back onto the last page',
      (tester) async {
    // migrated: the old model gated the boundary move on hasNextBoundary and had
    // to avoid sliding onto an empty slot. In the new model the window's outer
    // edge ALWAYS bounces (never slides off) and just reports onReachedEndEdge;
    // whether a chapter actually follows is the host's decision, not the
    // viewport's. So the equivalent guarantee is: the edge fires exactly once,
    // and the reader stays parked on the last page (raw 2).
    final pages = _localPages(3);
    final mapping = buildSpreadMapping(
      pageCount: pages.length,
      doublePages: false,
      splitWide: false,
      splitInvert: false,
      isWide: (_) => false,
    );
    final controller = PagedReaderController();
    final reported = <int>[];
    var endEdgeHits = 0;

    await _pumpViewport(
      tester,
      controller: controller,
      mapping: mapping,
      pages: pages,
      initialDisplayIndex: 2,
      onRawPageChanged: reported.add,
      callbacks: _callbacks(),
      onReachedEndEdge: () => endEdgeHits += 1,
      animateTransitions: true,
    );

    await tester.timedDrag(
      find.byType(PagedReaderViewport),
      const Offset(-80, 0),
      const Duration(milliseconds: 80),
    );
    await tester.pumpAndSettle();

    expect(endEdgeHits, 1);
    // Bounced back to the last page — never advanced to a non-existent slot.
    expect(reported.last, 2);
    expect(controller.isAtLast, isTrue);
  });

  testWidgets('last display swipe settles on the chapter transition first',
      (tester) async {
    // migrated: the trailing transition card is an ordinary in-window slot now,
    // so the first fling pages onto it ('Finished') and only the second fling —
    // off the window's outer end — trips onReachedEndEdge.
    final pages = _localPages(3);
    final mapping = buildSpreadMapping(
      pageCount: pages.length,
      doublePages: false,
      splitWide: false,
      splitInvert: false,
      isWide: (_) => false,
    );
    final controller = PagedReaderController();
    var endEdgeHits = 0;

    await _pumpViewport(
      tester,
      controller: controller,
      mapping: mapping,
      pages: pages,
      initialDisplayIndex: 2,
      onRawPageChanged: (_) {},
      callbacks: _callbacks(),
      onReachedEndEdge: () => endEdgeHits += 1,
      animateTransitions: true,
      nextBoundary: const Text('Finished'),
    );

    await tester.timedDrag(
      find.byType(PagedReaderViewport),
      const Offset(-80, 0),
      const Duration(milliseconds: 80),
    );
    await tester.pumpAndSettle();

    expect(find.text('Finished'), findsOneWidget);
    expect(endEdgeHits, 0);

    await tester.timedDrag(
      find.byType(PagedReaderViewport),
      const Offset(-80, 0),
      const Duration(milliseconds: 80),
    );
    expect(endEdgeHits, 1);
    await tester.pumpAndSettle();

    expect(endEdgeHits, 1);
  });

  testWidgets('sub-threshold drag does not turn a double-page spread',
      (tester) async {
    final pages = _localPages(4);
    final mapping = buildSpreadMapping(
      pageCount: pages.length,
      doublePages: true,
      splitWide: false,
      splitInvert: false,
      isWide: (_) => false,
    );
    final reported = <int>[];
    final controller = PagedReaderController();

    await _pumpViewport(
      tester,
      controller: controller,
      mapping: mapping,
      pages: pages,
      initialDisplayIndex: 0,
      onRawPageChanged: reported.add,
      callbacks: _callbacks(),
    );
    reported.clear();

    // migrated: the turn threshold is now the FULL viewport extent for every
    // slot (spreads no longer turn at half distance), so a sub-threshold drag is
    // one below ~0.18 of the 300px viewport. A slow 40px drag stays under it — a
    // spread must not commit a turn any easier than a single page does.
    await tester.timedDrag(
      find.byType(PagedReaderViewport),
      const Offset(-40, 0),
      const Duration(milliseconds: 700),
    );
    await tester.pumpAndSettle();

    expect(reported, isEmpty);
  });

  testWidgets('short fling turns a double-page spread', (tester) async {
    final pages = _localPages(4);
    final mapping = buildSpreadMapping(
      pageCount: pages.length,
      doublePages: true,
      splitWide: false,
      splitInvert: false,
      isWide: (_) => false,
    );
    final reported = <int>[];
    final controller = PagedReaderController();

    await _pumpViewport(
      tester,
      controller: controller,
      mapping: mapping,
      pages: pages,
      initialDisplayIndex: 0,
      onRawPageChanged: reported.add,
      callbacks: _callbacks(),
    );
    reported.clear();

    await tester.timedDrag(
      find.byType(PagedReaderViewport),
      const Offset(-64, 0),
      const Duration(milliseconds: 80),
    );
    await tester.pumpAndSettle();

    expect(reported, [3]);
  });

  testWidgets('reverse short fling turns a double-page spread', (tester) async {
    final pages = _localPages(4);
    final mapping = buildSpreadMapping(
      pageCount: pages.length,
      doublePages: true,
      splitWide: false,
      splitInvert: false,
      isWide: (_) => false,
    );
    final reported = <int>[];
    final controller = PagedReaderController();

    await _pumpViewport(
      tester,
      controller: controller,
      mapping: mapping,
      pages: pages,
      initialDisplayIndex: 0,
      onRawPageChanged: reported.add,
      callbacks: _callbacks(),
      reverse: true,
    );
    reported.clear();

    await tester.timedDrag(
      find.byType(PagedReaderViewport),
      const Offset(64, 0),
      const Duration(milliseconds: 80),
    );
    await tester.pumpAndSettle();

    expect(reported, [3]);
  });

  testWidgets('paged reader starts at neutral zoom', (tester) async {
    final pages = _localPages(1);
    final mapping = buildSpreadMapping(
      pageCount: pages.length,
      doublePages: false,
      splitWide: false,
      splitInvert: false,
      isWide: (_) => false,
    );

    await _pumpViewport(
      tester,
      controller: PagedReaderController(),
      mapping: mapping,
      pages: pages,
      initialDisplayIndex: 0,
      onRawPageChanged: (_) {},
      callbacks: _callbacks(),
    );

    expect(_transformScales(tester).where((scale) => scale < 0.99), isEmpty);
  });

  testWidgets('wide paged images stay at neutral zoom on open', (tester) async {
    final pages = _localPages(1);
    final mapping = buildSpreadMapping(
      pageCount: pages.length,
      doublePages: true,
      splitWide: false,
      splitInvert: false,
      isWide: (_) => true,
    );

    await _pumpViewport(
      tester,
      controller: PagedReaderController(),
      mapping: mapping,
      pages: pages,
      initialDisplayIndex: 0,
      onRawPageChanged: (_) {},
      callbacks: _callbacks(),
    );
    await tester.pump(const Duration(milliseconds: 700));

    expect(_largestScale(tester), lessThan(1.01));
  });

  testWidgets('pinch respects disable zoom out', (tester) async {
    final pages = _localPages(1);
    final mapping = buildSpreadMapping(
      pageCount: pages.length,
      doublePages: false,
      splitWide: false,
      splitInvert: false,
      isWide: (_) => false,
    );

    await _pumpViewport(
      tester,
      controller: PagedReaderController(),
      mapping: mapping,
      pages: pages,
      initialDisplayIndex: 0,
      onRawPageChanged: (_) {},
      callbacks: _callbacks(),
    );
    await _pinchViewportIn(tester);
    expect(_smallestScale(tester), lessThan(0.75));

    await _pumpViewport(
      tester,
      controller: PagedReaderController(),
      mapping: mapping,
      pages: pages,
      initialDisplayIndex: 0,
      onRawPageChanged: (_) {},
      callbacks: _callbacks(),
      disableZoomOut: true,
    );
    await _pinchViewportIn(tester);
    expect(_smallestScale(tester), greaterThan(0.99));
  });

  testWidgets('double tap toggles back to neutral zoom', (tester) async {
    final pages = _localPages(1);
    final mapping = buildSpreadMapping(
      pageCount: pages.length,
      doublePages: false,
      splitWide: false,
      splitInvert: false,
      isWide: (_) => false,
    );

    await _pumpViewport(
      tester,
      controller: PagedReaderController(),
      mapping: mapping,
      pages: pages,
      initialDisplayIndex: 0,
      onRawPageChanged: (_) {},
      callbacks: _callbacks(),
    );

    await _doubleTapViewport(tester);
    expect(_largestScale(tester), greaterThan(1.9));

    await _doubleTapViewport(tester);
    expect(_largestScale(tester), lessThan(1.01));
  });

  testWidgets('zoomed pan carries after a fling', (tester) async {
    final pages = _localPages(1);
    final mapping = buildSpreadMapping(
      pageCount: pages.length,
      doublePages: false,
      splitWide: false,
      splitInvert: false,
      isWide: (_) => false,
    );

    await _pumpViewport(
      tester,
      controller: PagedReaderController(),
      mapping: mapping,
      pages: pages,
      initialDisplayIndex: 0,
      onRawPageChanged: (_) {},
      callbacks: _callbacks(),
    );
    await _doubleTapViewport(tester);

    await tester.timedDrag(
      find.byType(PagedReaderViewport),
      const Offset(-90, 0),
      const Duration(milliseconds: 80),
    );
    final releasePosition = _leftmostTranslation(tester);

    await tester.pump(const Duration(milliseconds: 80));

    expect(_leftmostTranslation(tester), lessThan(releasePosition - 1));
    await tester.pumpAndSettle();
  });

  testWidgets('zoomed edge swipe turns the page', (tester) async {
    final pages = _localPages(2);
    final mapping = buildSpreadMapping(
      pageCount: pages.length,
      doublePages: false,
      splitWide: false,
      splitInvert: false,
      isWide: (_) => false,
    );
    final reported = <int>[];
    final controller = PagedReaderController();

    await _pumpViewport(
      tester,
      controller: controller,
      mapping: mapping,
      pages: pages,
      initialDisplayIndex: 0,
      onRawPageChanged: reported.add,
      callbacks: _callbacks(),
    );
    await _doubleTapViewport(tester);
    reported.clear();

    controller.next();
    await tester.pumpAndSettle();
    expect(reported, isEmpty);

    await tester.timedDrag(
      find.byType(PagedReaderViewport),
      const Offset(-90, 0),
      const Duration(milliseconds: 80),
    );
    await tester.pumpAndSettle();

    expect(reported, [1]);
  });

  testWidgets('two-finger hold does not start long press', (tester) async {
    final pages = _localPages(1);
    final mapping = buildSpreadMapping(
      pageCount: pages.length,
      doublePages: false,
      splitWide: false,
      splitInvert: false,
      isWide: (_) => false,
    );
    var starts = 0;
    var ends = 0;
    var cancels = 0;

    await _pumpViewport(
      tester,
      controller: PagedReaderController(),
      mapping: mapping,
      pages: pages,
      initialDisplayIndex: 0,
      onRawPageChanged: (_) {},
      callbacks: _callbacks(
        onLongPressStart: (_) => starts += 1,
        onLongPressEnd: () => ends += 1,
        onLongPressCancel: () => cancels += 1,
      ),
    );

    final center = tester.getCenter(find.byType(PagedReaderViewport));
    final first = await tester.startGesture(
      center - const Offset(24, 0),
      pointer: 1,
    );
    final second = await tester.startGesture(
      center + const Offset(24, 0),
      pointer: 2,
    );

    await tester.pump(const Duration(milliseconds: 600));

    expect(starts, 0);
    expect(ends, 0);
    expect(cancels, 0);

    await second.up();
    await first.up();
  });

  testWidgets('long press does not reach ancestor shortcuts', (tester) async {
    final pages = _localPages(1);
    final mapping = buildSpreadMapping(
      pageCount: pages.length,
      doublePages: false,
      splitWide: false,
      splitInvert: false,
      isWide: (_) => false,
    );
    var starts = 0;
    var ancestorLongPresses = 0;

    await _pumpViewport(
      tester,
      controller: PagedReaderController(),
      mapping: mapping,
      pages: pages,
      initialDisplayIndex: 0,
      onRawPageChanged: (_) {},
      callbacks: _callbacks(onLongPressStart: (_) => starts += 1),
      wrapper: (child) => GestureDetector(
        onLongPress: () => ancestorLongPresses += 1,
        child: child,
      ),
    );

    final center = tester.getCenter(find.byType(PagedReaderViewport));
    final gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 600));

    expect(starts, 1);
    expect(ancestorLongPresses, 0);

    await gesture.up();
  });

  testWidgets('two-finger hold does not reach ancestor shortcuts',
      (tester) async {
    final pages = _localPages(1);
    final mapping = buildSpreadMapping(
      pageCount: pages.length,
      doublePages: false,
      splitWide: false,
      splitInvert: false,
      isWide: (_) => false,
    );
    var ancestorLongPresses = 0;

    await _pumpViewport(
      tester,
      controller: PagedReaderController(),
      mapping: mapping,
      pages: pages,
      initialDisplayIndex: 0,
      onRawPageChanged: (_) {},
      callbacks: _callbacks(),
      wrapper: (child) => GestureDetector(
        onLongPress: () => ancestorLongPresses += 1,
        child: child,
      ),
    );

    final center = tester.getCenter(find.byType(PagedReaderViewport));
    final first = await tester.startGesture(
      center - const Offset(24, 0),
      pointer: 1,
    );
    final second = await tester.startGesture(
      center + const Offset(24, 0),
      pointer: 2,
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(ancestorLongPresses, 0);

    await second.up();
    await first.up();
  });

  testWidgets('second pointer cancels an active long press', (tester) async {
    final pages = _localPages(1);
    final mapping = buildSpreadMapping(
      pageCount: pages.length,
      doublePages: false,
      splitWide: false,
      splitInvert: false,
      isWide: (_) => false,
    );
    var starts = 0;
    var ends = 0;
    var cancels = 0;

    await _pumpViewport(
      tester,
      controller: PagedReaderController(),
      mapping: mapping,
      pages: pages,
      initialDisplayIndex: 0,
      onRawPageChanged: (_) {},
      callbacks: _callbacks(
        onLongPressStart: (_) => starts += 1,
        onLongPressEnd: () => ends += 1,
        onLongPressCancel: () => cancels += 1,
      ),
    );

    final center = tester.getCenter(find.byType(PagedReaderViewport));
    final first = await tester.startGesture(center, pointer: 1);
    await tester.pump(const Duration(milliseconds: 520));
    expect(starts, 1);

    final second = await tester.startGesture(
      center + const Offset(40, 0),
      pointer: 2,
    );
    await tester.pump();

    expect(ends, 0);
    expect(cancels, 1);

    await second.up();
    await first.up();
  });

  testWidgets('two-finger tap does not leak into reader tap actions',
      (tester) async {
    final pages = _localPages(1);
    final mapping = buildSpreadMapping(
      pageCount: pages.length,
      doublePages: false,
      splitWide: false,
      splitInvert: false,
      isWide: (_) => false,
    );
    var taps = 0;

    await _pumpViewport(
      tester,
      controller: PagedReaderController(),
      mapping: mapping,
      pages: pages,
      initialDisplayIndex: 0,
      onRawPageChanged: (_) {},
      callbacks: _callbacks(onTap: () => taps += 1),
    );

    final center = tester.getCenter(find.byType(PagedReaderViewport));
    final first = await tester.startGesture(
      center - const Offset(24, 0),
      pointer: 1,
    );
    final second = await tester.startGesture(
      center + const Offset(24, 0),
      pointer: 2,
    );

    await second.up();
    await first.up();
    await tester.pump(const Duration(milliseconds: 300));

    expect(taps, 0);
  });
}
