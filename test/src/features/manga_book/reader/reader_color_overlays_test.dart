// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Custom-filter overlay contract (design §2.4 layer 3): the color math
// (brightness alpha, grayscale/invert matrices), the leaf-overlay behavior
// (draft ?? committed, inert-positive brightness), the chrome z-order
// (filters < flash < bars), and the zero-viewer-rebuild preview discipline.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/chrome/reader_color_overlays.dart';

/// Applies a 4x5 color matrix to an RGBA pixel (0..255 scale), like Skia.
List<double> _apply(List<double> m, List<double> p) => [
  for (var r = 0; r < 4; r++)
    m[r * 5] * p[0] +
        m[r * 5 + 1] * p[1] +
        m[r * 5 + 2] * p[2] +
        m[r * 5 + 3] * p[3] +
        m[r * 5 + 4],
];

void main() {
  test('overlay math matches Komikku: brightness, grayscale and invert', () {
    expect(brightnessOverlayAlpha(-75), 0.75);
    expect(brightnessOverlayAlpha(-1), 0.01);
    expect(brightnessOverlayAlpha(-50), 0.5);
    expect(brightnessOverlayAlpha(-200), 1.0, reason: 'clamped');
    expect(applicationBrightnessFor(100), 1.0);
    expect(applicationBrightnessFor(50), 0.5);
    expect(applicationBrightnessFor(200), 1.0, reason: 'clamped');
    expect(applicationBrightnessFor(0), isNull);
    expect(applicationBrightnessFor(-50), isNull);

    const white = <double>[255, 255, 255, 255];
    const red = <double>[255, 0, 0, 255];
    const black = <double>[0, 0, 0, 255];
    expect(_apply(kGrayscaleColorMatrix, white), [255, 255, 255, 255]);
    final gray = _apply(kGrayscaleColorMatrix, red);
    expect(gray[0], closeTo(0.213 * 255, 0.001));
    expect(gray[0], gray[1]);
    expect(gray[1], gray[2]);
    expect(gray[3], 255, reason: 'alpha untouched');

    expect(_apply(kInvertColorMatrix, white), [0, 0, 0, 255]);
    expect(_apply(kInvertColorMatrix, black), [255, 255, 255, 255]);
  });
}
