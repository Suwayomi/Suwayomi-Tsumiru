// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Reproduction of the reported "back-scroll snap": with webtoon strips taller
// than the viewport, ScrollablePositionedList realigns to the PREVIOUS item's
// top when you scroll backward past the top of the current strip, instead of
// revealing the previous strip's bottom continuously.
//
// We assert the SMOOTH expectation (a small backward drag moves the anchored
// item by a small amount). If SPL snaps, the item's leading edge jumps by far
// more than the drag — the test fails, documenting the bug. The fix (a
// pixel-scrolled foundation) must make this pass.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

void main() {
  testWidgets(
      'backward scroll past a tall strip does not snap the previous strip to top',
      (tester) async {
    const viewport = 600.0;
    const stripHeight = 1500.0; // 2.5x viewport — a typical manhwa strip
    final itemScrollController = ItemScrollController();
    final positionsListener = ItemPositionsListener.create();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              height: viewport,
              width: 400,
              child: ScrollablePositionedList.builder(
                itemScrollController: itemScrollController,
                itemPositionsListener: positionsListener,
                itemCount: 8,
                itemBuilder: (context, i) => Container(
                  height: stripHeight,
                  color: i.isEven ? Colors.red : Colors.blue,
                  alignment: Alignment.center,
                  child: Text('strip$i'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Anchor strip 4 at the top of the viewport.
    itemScrollController.jumpTo(index: 4);
    await tester.pumpAndSettle();

    double leadingEdgeOf(int index) => positionsListener.itemPositions.value
        .firstWhere((p) => p.index == index)
        .itemLeadingEdge;

    expect(leadingEdgeOf(4), closeTo(0.0, 0.001),
        reason: 'strip4 starts anchored at the viewport top');

    // Scroll BACKWARD (drag content downward by 120px) from a point INSIDE the
    // viewport. Smooth behavior: strip4 moves down ~120/600 = 0.2 of the
    // viewport and strip3 peeks in from the top. A snap realigns strip3's TOP
    // to 0 and shoves strip4 far down (≈ stripHeight/viewport = 2.5).
    await tester.dragFrom(const Offset(200, 300), const Offset(0, 120));
    await tester.pumpAndSettle();

    final newLeading = leadingEdgeOf(4);
    expect(
      newLeading,
      closeTo(0.2, 0.08),
      reason: 'strip4 should move down ~0.2 viewport, not snap. '
          'Got $newLeading (a large value ~2.5 means SPL snapped strip3 to top).',
    );
  });

  testWidgets(
      'a rebuild during backward scroll does NOT re-anchor/snap the position',
      (tester) async {
    const viewport = 600.0;
    const stripHeight = 1500.0;
    final itemScrollController = ItemScrollController();
    final positionsListener = ItemPositionsListener.create();
    final rebuildTick = ValueNotifier<int>(0);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              height: viewport,
              width: 400,
              // Mirrors the real reader: a ValueNotifier the position listener
              // bumps on every scroll tick, rebuilding the list subtree.
              child: ValueListenableBuilder<int>(
                valueListenable: rebuildTick,
                builder: (context, tick, _) =>
                    ScrollablePositionedList.builder(
                  itemScrollController: itemScrollController,
                  itemPositionsListener: positionsListener,
                  itemCount: 8,
                  itemBuilder: (context, i) => Container(
                    key: ValueKey('strip$i-$tick'),
                    height: stripHeight,
                    color: i.isEven ? Colors.red : Colors.blue,
                    child: Text('strip$i tick$tick'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    itemScrollController.jumpTo(index: 4);
    await tester.pumpAndSettle();

    double leadingEdgeOf(int index) => positionsListener.itemPositions.value
        .firstWhere((p) => p.index == index)
        .itemLeadingEdge;

    // Scroll backward a bit, then trigger a rebuild mid-scroll (as the position
    // listener does) and verify the anchored strip didn't jump.
    await tester.dragFrom(const Offset(200, 300), const Offset(0, 120));
    await tester.pump();
    final before = leadingEdgeOf(4);
    rebuildTick.value++; // the rebuild the real reader fires every scroll tick
    await tester.pumpAndSettle();
    final after = leadingEdgeOf(4);

    expect(after, closeTo(before, 0.05),
        reason: 'a rebuild must not move the anchored strip. '
            'before=$before after=$after (a jump means rebuild re-anchored SPL)');
  });
}
