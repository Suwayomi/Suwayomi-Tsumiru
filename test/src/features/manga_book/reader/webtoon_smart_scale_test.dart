// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Long-strip smart scale: on wide screens the webtoon strip is capped
// to the chosen aspect column; on tall/portrait screens it stays full width
// (shrink iff screenRatio > desiredRatio).

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/enum.dart';

void main() {
  group('WebtoonScaleType.maxContentWidth', () {
    test('fitScreen never caps (returns full width)', () {
      expect(WebtoonScaleType.fitScreen.maxContentWidth(400, 800), 400);
      expect(WebtoonScaleType.fitScreen.maxContentWidth(1600, 900), 1600);
    });

    test('landscape screen is capped to the aspect column', () {
      // 1600x900 landscape: 4:3 → 900 * 3/4 = 675 (< 1600) so cap to 675.
      expect(WebtoonScaleType.ratio4to3.maxContentWidth(1600, 900), 675);
      // 3:2 → 900 * 2/3 = 600.
      expect(WebtoonScaleType.ratio3to2.maxContentWidth(1600, 900), 600);
      // 16:9 → 900 * 9/16 = 506.25.
      expect(WebtoonScaleType.ratio16to9.maxContentWidth(1600, 900), 506.25);
      // 20:9 (narrowest) → 900 * 9/20 = 405.
      expect(WebtoonScaleType.ratio20to9.maxContentWidth(1600, 900), 405);
    });

    test('tall portrait phone stays full width for moderate ratios', () {
      // 400x800 (1:2). 4:3 desired = 800*0.75 = 600 > 400 → full width.
      expect(WebtoonScaleType.ratio4to3.maxContentWidth(400, 800), 400);
      // 3:2 desired = 800*2/3 ≈ 533 > 400 → full width.
      expect(WebtoonScaleType.ratio3to2.maxContentWidth(400, 800), 400);
    });

    test('only the widest ratios trim a 2:1 phone', () {
      // 400x800: 16:9 desired = 800*9/16 = 450 > 400 → full width.
      expect(WebtoonScaleType.ratio16to9.maxContentWidth(400, 800), 400);
      // 20:9 desired = 800*9/20 = 360 < 400 → cap to 360.
      expect(WebtoonScaleType.ratio20to9.maxContentWidth(400, 800), 360);
    });

    test('narrower ratios cap more aggressively on the same screen', () {
      final w4to3 = WebtoonScaleType.ratio4to3.maxContentWidth(1200, 800);
      final w20to9 = WebtoonScaleType.ratio20to9.maxContentWidth(1200, 800);
      expect(w20to9, lessThan(w4to3));
      expect(w4to3, 600); // 800 * 0.75
      expect(w20to9, 360); // 800 * 0.45
    });
  });
}
