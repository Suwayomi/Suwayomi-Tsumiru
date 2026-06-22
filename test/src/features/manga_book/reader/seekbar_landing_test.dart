// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Reproduces the seek-bar landing bug WITHOUT a device. The webtoon reader is
// a ScrollablePositionedList of variable-height pages. The seek bar calls
// itemScrollController.jumpTo(index:). On-device, a single tap landed several
// pages away from the target. These tests isolate the cause by modelling the
// reader's item sizing in three escalating ways:
//
//   A. items have their real (variable) height from the first frame
//   B. items start at a guessed placeholder height, then GROW to their real
//      height one frame later (what MeasureSize + async image decode does)
//   C. like B, but the placeholder is the running AVERAGE of already-measured
//      pages (exactly what the live reader does)
//
// The first that fails tells us what actually breaks the landing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// Real rendered heights for 40 pages — deliberately wildly variable, like
/// real webtoon strips (some ~1 screen, some ~5 screens).
List<double> _realHeights(double screen) => [
      for (var i = 0; i < 40; i++)
        screen * (i % 5 == 0 ? 5.0 : (i % 3 == 0 ? 3.0 : 1.2)),
    ];

/// Returns the index of the page currently pinned to the viewport top.
int _topIndex(ItemPositionsListener listener) {
  final positions = listener.itemPositions.value
      .where((p) => p.itemTrailingEdge > 0)
      .toList()
    ..sort((a, b) => a.itemLeadingEdge.compareTo(b.itemLeadingEdge));
  return positions.isEmpty ? -1 : positions.first.index;
}

void main() {
  const screen = 800.0;

  Future<void> pumpList(
    WidgetTester tester, {
    required ItemScrollController controller,
    required ItemPositionsListener listener,
    required Widget Function(BuildContext, int) itemBuilder,
  }) async {
    tester.view.physicalSize = const Size(400, screen);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScrollablePositionedList.separated(
            itemScrollController: controller,
            itemPositionsListener: listener,
            itemCount: 40,
            minCacheExtent: screen * 3,
            itemBuilder: itemBuilder,
            separatorBuilder: (_, __) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  testWidgets('A: stable variable heights — jumpTo lands exactly',
      (tester) async {
    final controller = ItemScrollController();
    final listener = ItemPositionsListener.create();
    final heights = _realHeights(screen);

    await pumpList(
      tester,
      controller: controller,
      listener: listener,
      itemBuilder: (_, i) => SizedBox(height: heights[i], width: 400),
    );

    controller.jumpTo(index: 20);
    await tester.pumpAndSettle();

    expect(_topIndex(listener), 20);
  });

  testWidgets('B: items grow after first layout — jumpTo landing',
      (tester) async {
    final controller = ItemScrollController();
    final listener = ItemPositionsListener.create();
    final heights = _realHeights(screen);

    await pumpList(
      tester,
      controller: controller,
      listener: listener,
      itemBuilder: (_, i) => _GrowingPage(
        placeholder: screen * 0.7,
        real: heights[i],
      ),
    );

    controller.jumpTo(index: 20);
    await tester.pump(); // jump frame
    await tester.pump(const Duration(milliseconds: 16)); // pages "decode"
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pumpAndSettle();

    expect(_topIndex(listener), 20);
  });

  // This is the offline seek bug AND its fix, captured off-device.
  //
  // The offline (file://) ServerImage branch skips progressIndicatorBuilder and
  // renders a bare Image, which is ZERO px tall until the local file decodes and
  // then pops to full height. With placeholder == 0 the jump lands on the wrong
  // page; reserving the placeholder height first (what the frameBuilder fix in
  // the reader does) makes the jump land true. If the reservation regresses,
  // the `reserved` case below starts landing wrong and this test fails.
  testWidgets('D: offline pages — zero-height pops mis-land; reserved lands true',
      (tester) async {
    final heights = _realHeights(screen);

    Future<int> landingWith(double placeholder) async {
      final controller = ItemScrollController();
      final listener = ItemPositionsListener.create();
      await pumpList(
        tester,
        controller: controller,
        listener: listener,
        itemBuilder: (_, i) => _GrowingPage(placeholder: placeholder, real: heights[i]),
      );
      controller.jumpTo(index: 20);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pumpAndSettle();
      return _topIndex(listener);
    }

    // The bug: no reserved height -> jump does not land on the target.
    expect(await landingWith(0), isNot(20));
    // The fix: reserve the placeholder height first -> jump lands true.
    expect(await landingWith(screen * 0.7), 20);
  });

  testWidgets('C: faithful mini-reader (rebuild on measure + on position)',
      (tester) async {
    tester.view.physicalSize = const Size(400, screen);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final controller = ItemScrollController();
    final key = GlobalKey<_MiniReaderState>();
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: _MiniReader(key: key, controller: controller))),
    );
    // let the initial pages "decode" and measure
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }

    key.currentState!.seek(20);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pumpAndSettle();

    expect(_topIndex(key.currentState!.listener), 20);
  });
}

/// A faithful miniature of MultiChapterContinuousReaderMode's sizing + listener
/// loop: placeholder = measured[i] ?? average(measured) ?? 0.7-screen; each page
/// measures its real height one frame after building (writes to the shared map
/// and rebuilds); the position listener rebuilds on every change. The seek sets
/// the current index then jumpTo(index:), exactly like the real onChanged.
class _MiniReader extends StatefulWidget {
  const _MiniReader({super.key, required this.controller});
  final ItemScrollController controller;
  @override
  State<_MiniReader> createState() => _MiniReaderState();
}

class _MiniReaderState extends State<_MiniReader> {
  final listener = ItemPositionsListener.create();
  final Map<int, double> measured = {};
  late final List<double> real;
  static const screen = 800.0;
  int currentIndex = 0;

  @override
  void initState() {
    super.initState();
    real = _realHeights(screen);
    listener.itemPositions.addListener(_onPositions);
  }

  @override
  void dispose() {
    listener.itemPositions.removeListener(_onPositions);
    super.dispose();
  }

  void _onPositions() {
    final positions = listener.itemPositions.value
        .where((p) => p.itemTrailingEdge > 0 && p.itemLeadingEdge < 1)
        .toList()
      ..sort((a, b) => a.itemLeadingEdge.compareTo(b.itemLeadingEdge));
    if (positions.isEmpty) return;
    final top = positions.first.index;
    if (top != currentIndex && mounted) {
      setState(() => currentIndex = top);
    }
  }

  void seek(int index) {
    setState(() => currentIndex = index);
    widget.controller.jumpTo(index: index);
  }

  double _placeholder() {
    if (measured.isEmpty) return screen * 0.7;
    return measured.values.reduce((a, b) => a + b) / measured.length;
  }

  @override
  Widget build(BuildContext context) {
    return ScrollablePositionedList.separated(
      itemScrollController: widget.controller,
      itemPositionsListener: listener,
      itemCount: 40,
      minCacheExtent: screen * 3,
      separatorBuilder: (_, __) => const SizedBox.shrink(),
      itemBuilder: (context, i) {
        final h = measured[i] ?? _placeholder();
        return _MeasuringPage(
          height: h,
          realHeight: real[i],
          alreadyMeasured: measured.containsKey(i),
          onMeasured: (rh) {
            if (!measured.containsKey(i) && mounted) {
              setState(() => measured[i] = rh);
            }
          },
        );
      },
    );
  }
}

/// Builds at [height]; one frame later reports its [realHeight] (decode) unless
/// it was [alreadyMeasured]. Mirrors ServerImage + MeasureSize.
class _MeasuringPage extends StatefulWidget {
  const _MeasuringPage({
    required this.height,
    required this.realHeight,
    required this.alreadyMeasured,
    required this.onMeasured,
  });
  final double height;
  final double realHeight;
  final bool alreadyMeasured;
  final ValueChanged<double> onMeasured;

  @override
  State<_MeasuringPage> createState() => _MeasuringPageState();
}

class _MeasuringPageState extends State<_MeasuringPage> {
  @override
  void initState() {
    super.initState();
    if (!widget.alreadyMeasured) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onMeasured(widget.realHeight);
      });
    }
  }

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: widget.height, width: 400);
}

/// A page that renders at [placeholder] height on its first build, then grows
/// to [real] one frame later — exactly what an async image decode does to a
/// page that was reserving a guessed height.
class _GrowingPage extends StatefulWidget {
  const _GrowingPage({required this.placeholder, required this.real});
  final double placeholder;
  final double real;

  @override
  State<_GrowingPage> createState() => _GrowingPageState();
}

class _GrowingPageState extends State<_GrowingPage> {
  late double _height = widget.placeholder;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _height = widget.real);
    });
  }

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: _height, width: 400);
}
