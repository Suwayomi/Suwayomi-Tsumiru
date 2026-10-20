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
  });
}
