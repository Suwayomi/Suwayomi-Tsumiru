// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Pins the value→platform-call decision for positive custom-brightness: only
// values >0 set an app-window brightness target (0..1); 0/negatives return
// null so the black dim overlay (brightnessOverlayAlpha) handles them instead.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/chrome/reader_color_overlays.dart';

void main() {
  group('applicationBrightnessFor', () {
    test('positive values map to value/100, clamped to 0..1', () {
      expect(applicationBrightnessFor(100), 1.0);
      expect(applicationBrightnessFor(50), 0.5);
      expect(applicationBrightnessFor(1), 0.01);
      expect(applicationBrightnessFor(200), 1.0, reason: 'clamped');
    });

    test('0 and negatives return null (black-dim territory)', () {
      expect(applicationBrightnessFor(0), isNull);
      expect(applicationBrightnessFor(-30), isNull);
      expect(applicationBrightnessFor(-75), isNull);
    });
  });
}
