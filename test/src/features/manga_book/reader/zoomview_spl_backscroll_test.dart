// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// FAITHFUL reproduction of the mobile-only back-scroll snap.
//
// On Android/iOS the reader wraps its ScrollablePositionedList in a ZoomView,
// wired through ScrollOffsetToScrollController exactly as the reader does.
// ZoomView drives scrolling itself: it reads `controller.position.pixels`,
// adds the pan delta, and `jumpTo`s the absolute offset (and runs flings via
// `position.drag`). SPL's position is a CENTER-sliver ScrollPosition whose
// minScrollExtent depends on the measured heights of items ABOVE the anchor.
//
// Each page image (`ServerImage`) has NO reserved height: it lays out as a
// ~0.7-viewport placeholder, then grows to ~9 viewports once the image DECODES
// — and the decode lands several frames AFTER a fling settles. So when you
// scroll up into a previously-disposed strip (a 9-viewport strip dwarfs the
// 2-viewport cache, so it is evicted and re-enters collapsed), the fling
// traverses the whole collapsed 0.7vp strip and settles at the boundary (its
// top). THEN the image decodes and the strip grows, pinning the viewport at the
// TOP of the previous strip — the reported snap.
//
// This test instantiates the REAL ZoomView + SPL + adapter (ZoomView has no
// platform gate) and reproduces the settle-then-decode sequence deterministically.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:tachidesk_sorayomi/src/widgets/zoom/scroll_offset_to_scroll_controller.dart';
import 'package:zoom_view/zoom_view.dart';

const _viewport = 600.0;
const _full = 5400.0; // ~9 viewports
const _placeholder = 420.0; // 0.7 * viewport, the reader's placeholder ratio
const _decodeDelay = Duration(milliseconds: 250); // decode lands after settle

/// Mimics ServerImage: lays out at [_placeholder] on every (re)build, then
/// grows to [_full] [_decodeDelay] later, as the image decodes.
class _DecodingStrip extends StatefulWidget {
  const _DecodingStrip({required this.index, super.key});
  final int index;
  @override
  State<_DecodingStrip> createState() => _DecodingStripState();
}

class _DecodingStripState extends State<_DecodingStrip> {
  double _height = _placeholder;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_decodeDelay, () {
      if (mounted) setState(() => _height = _full);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
        height: _height,
        color: widget.index.isEven ? Colors.red : Colors.blue,
        alignment: Alignment.topCenter,
        child: Text('strip${widget.index}'),
      );
}

void main() {
  testWidgets('ZoomView-driven backward scroll snaps to previous strip top',
      (tester) async {
    final itemScrollController = ItemScrollController();
    final positions = ItemPositionsListener.create();
    final scrollOffsetController = ScrollOffsetController();
    final zoomController = ScrollOffsetToScrollController(
        scrollOffsetController: scrollOffsetController);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              height: _viewport,
              width: 400,
              child: ZoomView(
                controller: zoomController,
                scrollAxis: Axis.vertical,
                child: ScrollablePositionedList.builder(
                  itemScrollController: itemScrollController,
                  itemPositionsListener: positions,
                  scrollOffsetController: scrollOffsetController,
                  itemCount: 30,
                  minCacheExtent: _viewport * 2, // reader's verticalCacheMultiplier
                  itemBuilder: (context, i) =>
                      _DecodingStrip(index: i, key: ValueKey('strip$i')),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    int topMost() {
      var idx = 1 << 30;
      var lead = 2.0;
      for (final p in positions.itemPositions.value) {
        if (p.itemLeadingEdge < lead) {
          lead = p.itemLeadingEdge;
          idx = p.index;
        }
      }
      return idx;
    }

    double leadOf(int index) => positions.itemPositions.value
        .firstWhere((p) => p.index == index)
        .itemLeadingEdge;

    // Read down to ~strip 8 so the strips above are disposed (evicted from the
    // 2-viewport cache — each strip is 9 viewports).
    itemScrollController.jumpTo(index: 8);
    await tester.pumpAndSettle();
    await tester.pump(_decodeDelay + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    final readingStrip = topMost();
    expect(readingStrip, greaterThanOrEqualTo(7),
        reason: 'anchored on a mid-list strip with disposed strips above');

    // Scroll BACKWARD via a ZoomView touch fling (drag content DOWN). One
    // viewport-ish fling: should reveal the bottom of the previous strip.
    await tester.fling(
        find.byType(ZoomView), const Offset(0, 700), 1200);
    // Let the fling settle while the re-entered previous strip is still a
    // collapsed placeholder...
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final topAfterFling = topMost();
    final leadAfterFling = leadOf(topAfterFling);
    // ...then the image decodes and the strip grows.
    await tester.pump(_decodeDelay);
    await tester.pumpAndSettle();

    final topAfterDecode = topMost();
    final leadAfterDecode = leadOf(topAfterDecode);

    // ignore: avoid_print
    print('reading=$readingStrip | afterFling top=$topAfterFling '
        'lead=${leadAfterFling.toStringAsFixed(2)} | afterDecode top=$topAfterDecode '
        'lead=${leadAfterDecode.toStringAsFixed(2)}');

    // Correct behaviour: after decode the top strip shows its BOTTOM (lead
    // ~-8.x) or we are smoothly mid-strip. The SNAP pins the previous strip's
    // TOP at the viewport top (lead ~0) after it grows.
    expect(leadAfterDecode, lessThan(-1.0),
        reason: 'SNAP REPRODUCED: after decode the top strip ($topAfterDecode) '
            'is pinned near its top (lead=$leadAfterDecode) instead of '
            'revealing its bottom. The collapsed placeholder let the fling '
            'overshoot to the previous strip top.');
  });
}
