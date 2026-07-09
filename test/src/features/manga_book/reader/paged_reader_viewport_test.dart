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
}) async {
  final viewport = ReaderInputScope(
    callbacks: callbacks,
    child: SizedBox(
      width: 300,
      height: 500,
      child: PagedReaderViewport(
        controller: controller,
        mapping: mapping,
        pages: pages,
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
        onPageWide: (_, __) {},
        onRawPageChanged: onRawPageChanged,
        pinchEnabled: true,
        doubleTapToZoom: true,
        disableZoomIn: false,
        disableZoomOut: disableZoomOut,
        navigateToPan: true,
        previousBoundary: previousBoundary,
        nextBoundary: nextBoundary,
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
  await tester.pump(const Duration(milliseconds: 280));
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

  testWidgets('next command at the last display uses boundary navigation',
      (tester) async {
    final pages = _localPages(3);
    final mapping = buildSpreadMapping(
      pageCount: pages.length,
      doublePages: false,
      splitWide: false,
      splitInvert: false,
      isWide: (_) => false,
    );
    final controller = PagedReaderController();
    var boundaryHits = 0;

    await _pumpViewport(
      tester,
      controller: controller,
      mapping: mapping,
      pages: pages,
      initialDisplayIndex: 2,
      onRawPageChanged: (_) {},
      callbacks: _callbacks(
        onNextBoundary: () {
          boundaryHits += 1;
          return true;
        },
      ),
    );

    controller.next();
    await tester.pump();

    expect(boundaryHits, 1);
  });

  testWidgets('next command lands on the chapter transition first',
      (tester) async {
    final pages = _localPages(3);
    final mapping = buildSpreadMapping(
      pageCount: pages.length,
      doublePages: false,
      splitWide: false,
      splitInvert: false,
      isWide: (_) => false,
    );
    final controller = PagedReaderController();
    var boundaryHits = 0;

    await _pumpViewport(
      tester,
      controller: controller,
      mapping: mapping,
      pages: pages,
      initialDisplayIndex: 2,
      onRawPageChanged: (_) {},
      callbacks: _callbacks(
        onNextBoundary: () {
          boundaryHits += 1;
          return true;
        },
      ),
      nextBoundary: const Text('Finished'),
    );

    expect(controller.isAtLast, isFalse);

    controller.next();
    await tester.pumpAndSettle();

    expect(find.text('Finished'), findsOneWidget);
    expect(controller.isAtLast, isTrue);
    expect(boundaryHits, 0);

    controller.next();
    await tester.pumpAndSettle();

    expect(boundaryHits, 1);
  });

  testWidgets('last display swipe settles through the chapter boundary',
      (tester) async {
    final pages = _localPages(3);
    final mapping = buildSpreadMapping(
      pageCount: pages.length,
      doublePages: false,
      splitWide: false,
      splitInvert: false,
      isWide: (_) => false,
    );
    final controller = PagedReaderController();
    var boundaryHits = 0;

    await _pumpViewport(
      tester,
      controller: controller,
      mapping: mapping,
      pages: pages,
      initialDisplayIndex: 2,
      onRawPageChanged: (_) {},
      callbacks: _callbacks(
        onNextBoundary: () {
          boundaryHits += 1;
          return true;
        },
      ),
      animateTransitions: true,
    );

    await tester.timedDrag(
      find.byType(PagedReaderViewport),
      const Offset(-80, 0),
      const Duration(milliseconds: 80),
    );

    expect(boundaryHits, 0);
    await tester.pumpAndSettle();
    expect(boundaryHits, 1);
  });

  testWidgets('last display swipe settles on the chapter transition first',
      (tester) async {
    final pages = _localPages(3);
    final mapping = buildSpreadMapping(
      pageCount: pages.length,
      doublePages: false,
      splitWide: false,
      splitInvert: false,
      isWide: (_) => false,
    );
    final controller = PagedReaderController();
    var boundaryHits = 0;

    await _pumpViewport(
      tester,
      controller: controller,
      mapping: mapping,
      pages: pages,
      initialDisplayIndex: 2,
      onRawPageChanged: (_) {},
      callbacks: _callbacks(
        onNextBoundary: () {
          boundaryHits += 1;
          return true;
        },
      ),
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
    expect(boundaryHits, 0);

    await tester.timedDrag(
      find.byType(PagedReaderViewport),
      const Offset(-80, 0),
      const Duration(milliseconds: 80),
    );
    expect(boundaryHits, 1);
    await tester.pumpAndSettle();

    expect(boundaryHits, 1);
  });

  testWidgets('short drag turns a double-page spread', (tester) async {
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
      const Offset(-80, 0),
      const Duration(milliseconds: 700),
    );
    await tester.pumpAndSettle();

    expect(reported, [2]);
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

    expect(reported, [2]);
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

    expect(reported, [2]);
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
