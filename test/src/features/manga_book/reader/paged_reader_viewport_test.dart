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
}) => ReaderInputCallbacks(
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
  DateTime Function()? clock,
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
        clock: clock ?? DateTime.now,
        controller: controller,
        window: window,
        initialDisplayIndex: initialDisplayIndex,
        axis: Axis.horizontal,
        reverse: reverse,
        animateTransitions: animateTransitions,
        pageFit: BoxFit.contain,
        pageSize: null,
        pagesAtNaturalSize: false,
        mouseScrollSpeed: 1.7,
        centerMargin: CenterMarginType.none,
        rotateWide: false,
        rotateWideInvert: false,
        reversePair: false,
        cropBorders: false,
        onPageWide: onPageWide ?? (_, _, _) {},
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
  for (final transform in tester.widgetList<Transform>(find.byType(Transform)))
    _xyScale(transform.transform.storage),
];

double _xyScale(Float64List storage) {
  final scaleX = math.sqrt(storage[0] * storage[0] + storage[1] * storage[1]);
  final scaleY = math.sqrt(storage[4] * storage[4] + storage[5] * storage[5]);
  return math.max(scaleX, scaleY);
}

double _largestScale(WidgetTester tester) =>
    _transformScales(tester).reduce(math.max);

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

void main() {
  testWidgets('next command at the last display hits the end edge', (
    tester,
  ) async {
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

  Future<List<double>> strandAndSettle(
    WidgetTester tester,
    PagedReaderController controller,
    double progress,
  ) async {
    controller.debugStrand(progress);
    await tester.pumpAndSettle();
    return [
      for (final transform in tester.widgetList<Transform>(
        find.ancestor(
          of: find.byType(ClipRect),
          matching: find.byType(Transform),
        ),
      ))
        transform.transform.storage[12],
    ];
  }

  testWidgets('a barely-started turn snaps back instead of skipping a page', (
    tester,
  ) async {
    // 0.19 clears the 0.18 turn threshold, so recovering through the normal
    // settle logic would advance the page.
    final pages = _localPages(3);
    final mapping = buildSpreadMapping(
      pageCount: pages.length,
      doublePages: false,
      splitWide: false,
      splitInvert: false,
      isWide: (_) => false,
    );
    final controller = PagedReaderController();
    final seen = <int>[];
    await _pumpViewport(
      tester,
      controller: controller,
      mapping: mapping,
      pages: pages,
      initialDisplayIndex: 0,
      onRawPageChanged: seen.add,
      callbacks: _callbacks(),
    );
    seen.clear();

    await strandAndSettle(tester, controller, 0.19);

    expect(seen, isEmpty, reason: 'recovery moved the reader off the page');
  });

  /// Drives the double-tap window, which compares wall clock time and so is
  /// untouched by the test binding's fake clock.
  Future<void> tapPair(
    WidgetTester tester,
    _FakeClock clock,
    Duration apart, {
    Offset? secondAt,
  }) async {
    final target = find.byType(PagedReaderViewport);
    await tester.tap(target);
    clock.advance(apart);
    await tester.pump(apart);
    if (secondAt == null) {
      await tester.tap(target);
    } else {
      await tester.tapAt(secondAt);
    }
    await tester.pump();
    await tester.pumpAndSettle();
  }

  testWidgets('a 250ms double tap zooms', (tester) async {
    // Real double taps commonly land 130-235ms apart. 200ms missed them.
    final clock = _FakeClock();
    var menuToggles = 0;
    await _pumpViewport(
      tester,
      controller: PagedReaderController(),
      mapping: _singlePageMapping(),
      pages: _localPages(1),
      initialDisplayIndex: 0,
      onRawPageChanged: (_) {},
      callbacks: _callbacks(onTap: () => menuToggles++),
      clock: clock.now,
    );

    await tapPair(tester, clock, const Duration(milliseconds: 250));

    expect(_largestScale(tester), greaterThan(1.9));
    expect(menuToggles, 0);
  });

  for (final reduce in [true, false]) {
    testWidgets('double tap zoom with reduced motion=$reduce', (tester) async {
      final clock = _FakeClock();
      await _pumpViewport(
        tester,
        controller: PagedReaderController(),
        mapping: _singlePageMapping(),
        pages: _localPages(1),
        initialDisplayIndex: 0,
        onRawPageChanged: (_) {},
        callbacks: _callbacks(),
        clock: clock.now,
        wrapper: (child) => Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
            child: child,
          ),
        ),
      );

      final target = find.byType(PagedReaderViewport);
      await tester.tap(target);
      clock.advance(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(target);
      await tester.pump();

      if (reduce) {
        expect(_largestScale(tester), greaterThan(1.9));
      } else {
        expect(_largestScale(tester), lessThan(1.9));
      }
      await tester.pumpAndSettle();
    });
  }

  testWidgets('taps beyond the window stay two separate taps', (tester) async {
    final clock = _FakeClock();
    var menuToggles = 0;
    await _pumpViewport(
      tester,
      controller: PagedReaderController(),
      mapping: _singlePageMapping(),
      pages: _localPages(1),
      initialDisplayIndex: 0,
      onRawPageChanged: (_) {},
      callbacks: _callbacks(onTap: () => menuToggles++),
      clock: clock.now,
    );

    await tapPair(tester, clock, const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(_largestScale(tester), lessThan(1.01), reason: 'no zoom');
    expect(menuToggles, 2);
  });
}

SpreadMapping _singlePageMapping() => buildSpreadMapping(
  pageCount: 1,
  doublePages: false,
  splitWide: false,
  splitInvert: false,
  isWide: (_) => false,
);

/// Wall clock the double-tap window can be driven against.
class _FakeClock {
  DateTime _at = DateTime(2026);
  DateTime now() => _at;
  void advance(Duration by) => _at = _at.add(by);
}
