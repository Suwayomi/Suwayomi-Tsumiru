// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Pins down the GEOMETRY of the back-scroll snap.
//
// Each page image (`ServerImage`) lays out as a ~0.7-viewport placeholder until
// it decodes, then grows to ~9 viewports. The reported bug: scrolling up, when
// you settle with a collapsed previous strip's TOP at the viewport top and the
// image then decodes, the viewport stays pinned at that strip's top — skipping
// its ~9 viewports of content.
//
// SPL is a center sliver anchored at `positionedIndex`. The open question is
// which edge of a growing strip gets anchored. We settle with the collapsed
// strip's top at the viewport top, then grow it, and read where the viewport
// lands. lead≈0 after growth == the snap; lead≈-8.x == SPL anchored the bottom
// (no snap).

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

const _viewport = 600.0;
const _full = 5400.0; // ~9 viewports
const _placeholder = 420.0; // 0.7 * viewport

double _leadOf(ItemPositionsListener l, int index) => l.itemPositions.value
    .firstWhere((p) => p.index == index)
    .itemLeadingEdge;

/// Builds a list where exactly [collapsedIndex] is currently a placeholder
/// (controllable height); all other strips are full height. [aboveCount] full
/// strips sit ABOVE the collapsed one.
Widget _harness({
  required ItemScrollController controller,
  required ItemPositionsListener positions,
  required ScrollOffsetController offset,
  required ValueListenable<double> collapsedHeight,
  required int collapsedIndex,
  required int itemCount,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          height: _viewport,
          width: 400,
          child: ValueListenableBuilder<double>(
            valueListenable: collapsedHeight,
            builder: (context, h, _) => ScrollablePositionedList.builder(
              itemScrollController: controller,
              itemPositionsListener: positions,
              scrollOffsetController: offset,
              itemCount: itemCount,
              minCacheExtent: 0,
              itemBuilder: (context, i) => Container(
                height: i == collapsedIndex ? h : _full,
                color: i.isEven ? Colors.red : Colors.blue,
                alignment: Alignment.topCenter,
                child: Text('strip$i'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _settleCollapsedTopAtViewportTop(
  WidgetTester tester,
  ItemScrollController controller,
  ItemPositionsListener positions,
  ScrollOffsetController offset,
  int collapsedIndex,
) async {
  // Anchor the strip just BELOW the collapsed one at the viewport top, so the
  // collapsed strip is the (reverse-sliver) previous strip.
  controller.jumpTo(index: collapsedIndex + 1);
  await tester.pumpAndSettle();
  // Scroll up by the collapsed strip's height so its TOP reaches the viewport
  // top. animateScroll takes a relative delta; negative == scroll toward start.
  offset.animateScroll(
      offset: -_placeholder,
      duration: const Duration(milliseconds: 1),
      curve: Curves.linear);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'growing strip with NO strips above it anchors its bottom (no snap)',
      (tester) async {
    final controller = ItemScrollController();
    final positions = ItemPositionsListener.create();
    final offset = ScrollOffsetController();
    final collapsed = ValueNotifier<double>(_placeholder);

    await tester.pumpWidget(_harness(
      controller: controller,
      positions: positions,
      offset: offset,
      collapsedHeight: collapsed,
      collapsedIndex: 0,
      itemCount: 6,
    ));
    await tester.pumpAndSettle();
    await _settleCollapsedTopAtViewportTop(
        tester, controller, positions, offset, 0);

    collapsed.value = _full; // decode
    await tester.pumpAndSettle();
    final lead = _leadOf(positions, 0);
    // ignore: avoid_print
    print('no-strips-above: strip0 lead after decode = ${lead.toStringAsFixed(2)}');
    expect(lead, lessThan(-1.0),
        reason: 'with nothing above, SPL grows the strip upward (bottom '
            'anchored) — no snap. lead=$lead');
  });

  testWidgets(
      'growing strip WITH full strips above it — does its top stay pinned (snap)?',
      (tester) async {
    final controller = ItemScrollController();
    final positions = ItemPositionsListener.create();
    final offset = ScrollOffsetController();
    final collapsed = ValueNotifier<double>(_placeholder);

    // collapsed strip is index 3; strips 0,1,2 are full strips ABOVE it.
    await tester.pumpWidget(_harness(
      controller: controller,
      positions: positions,
      offset: offset,
      collapsedHeight: collapsed,
      collapsedIndex: 3,
      itemCount: 8,
    ));
    await tester.pumpAndSettle();
    await _settleCollapsedTopAtViewportTop(
        tester, controller, positions, offset, 3);

    final leadBefore = _leadOf(positions, 3);
    collapsed.value = _full; // decode
    await tester.pumpAndSettle();
    final leadAfter = _leadOf(positions, 3);
    // ignore: avoid_print
    print('strips-above: strip3 lead before=${leadBefore.toStringAsFixed(2)} '
        'after decode=${leadAfter.toStringAsFixed(2)}');

    // This documents whatever SPL actually does. If leadAfter ≈ 0 the top is
    // pinned == the snap; if ≈ -8.x the bottom anchored == no snap.
    expect(leadAfter, lessThan(-1.0),
        reason: 'SNAP if this fails: strip3 top pinned at viewport top after '
            'growth (leadAfter=$leadAfter) instead of revealing its bottom.');
  });
}
