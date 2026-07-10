// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_mode/infinity_continuous/infinity_continuous_utils.dart';

ItemPosition _p(int index, double leading, double trailing) =>
    ItemPosition(index: index, itemLeadingEdge: leading, itemTrailingEdge: trailing);

int? _select(List<ItemPosition> positions, int total) =>
    InfinityContinuousUtils.selectCurrentIndex(positions, total,
        minVisibleAreaThreshold: 0.05);

void main() {
  group('selectCurrentIndex', () {
    test('mid-scroll picks the largest visible page', () {
      // A tall page fills most of the screen; the next barely peeks in.
      final positions = [
        _p(10, -0.3, 0.7), // visible area 0.7
        _p(11, 0.7, 1.6), // visible area ~0.3
      ];
      expect(_select(positions, 34), 10);
    });

    test('#100: at the bottom, a small last page wins over a taller one', () {
      // Scrolled to the end: page 31 still fills the top, but the two short
      // trailing pages share the rest — the last page (33) has less area yet
      // its bottom (0.9) is within the viewport, so it is current.
      final positions = [
        _p(31, -0.7, 0.4), // area 0.4 (largest)
        _p(32, 0.4, 0.65), // area 0.25
        _p(33, 0.65, 0.9), // last page, area 0.25, bottom reached
      ];
      expect(_select(positions, 34), 33);
    });

    test('last page visible but bottom not yet reached → largest area', () {
      // The last page is on screen but extends past the viewport bottom
      // (trailingEdge > 1.0) — the user has not scrolled to the end.
      final positions = [
        _p(32, -0.4, 0.5), // area 0.5
        _p(33, 0.5, 1.5), // last page, bottom still below the fold
      ];
      expect(_select(positions, 34), 32);
    });

    test('short chapter resting at the top does NOT complete on open', () {
      // A 3-page chapter that fully fits the viewport, freshly opened: page 0 is
      // parked at the top (leadingEdge 0). Must NOT return the last page, or the
      // chapter marks read on open (false tracker bump + delete-on-read).
      final positions = [
        _p(0, 0.0, 0.33),
        _p(1, 0.33, 0.66),
        _p(2, 0.66, 0.9), // last page bottom within viewport, but at rest
      ];
      expect(_select(positions, 3), 0);
    });

    test('scrolled to the end of a short chapter (page 0 leaving) completes', () {
      // Same short chapter, but now scrolled: page 0 has slid above the viewport
      // top (leadingEdge < 0) — the user reached the end, so it completes.
      final positions = [
        _p(0, -0.5, 0.2),
        _p(1, 0.2, 0.6),
        _p(2, 0.6, 0.9),
      ];
      expect(_select(positions, 3), 2);
    });

    test('empty positions → null', () {
      expect(_select(const [], 34), isNull);
    });

    test('single-page total does not force the override', () {
      expect(_select([_p(0, 0.0, 0.8)], 1), 0);
    });
  });
}
