// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/crop/border_crop.dart';

/// Builds a [width]x[height] RGBA buffer filled with [border], then paints an
/// axis-aligned rectangle [rect] with [fill].
Uint8List _buffer(
  int width,
  int height,
  List<int> border,
  ({int left, int top, int right, int bottom})? rect,
  List<int>? fill,
) {
  final buf = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      final inside =
          rect != null &&
          x >= rect.left &&
          x < rect.right &&
          y >= rect.top &&
          y < rect.bottom;
      final c = inside ? fill! : border;
      buf[i] = c[0];
      buf[i + 1] = c[1];
      buf[i + 2] = c[2];
      buf[i + 3] = 255;
    }
  }
  return buf;
}

const _white = [255, 255, 255];
const _red = [255, 0, 0];

void main() {
  group('findContentRect', () {
    test('white border around a red center returns the inner rect', () {
      // 20x20 white with a red 8x8 center at (6,6)-(14,14).
      final rect = (left: 6, top: 6, right: 14, bottom: 14);
      final buf = _buffer(20, 20, _white, rect, _red);
      final result = findContentRect(buf, 20, 20);
      expect(result, isNotNull);
      expect(result!.left, 6);
      expect(result.top, 6);
      expect(result.right, 14);
      expect(result.bottom, 14);
      expect(result.width, 8);
      expect(result.height, 8);
    });

    test('asymmetric border trims each side independently', () {
      // Content 3..17 x, 2..12 y — different margins each side.
      final rect = (left: 3, top: 2, right: 17, bottom: 12);
      final buf = _buffer(20, 20, _white, rect, _red);
      final result = findContentRect(buf, 20, 20);
      expect(result, isNotNull);
      expect(result!.left, 3);
      expect(result.top, 2);
      expect(result.right, 17);
      expect(result.bottom, 12);
    });

    test('content reaching every edge returns null (no border)', () {
      final buf = _buffer(20, 20, _red, null, null);
      expect(findContentRect(buf, 20, 20), isNull);
    });

    test('degenerate input (bad dimensions) returns null', () {
      final buf = _buffer(10, 10, _white, null, null);
      expect(findContentRect(buf, 0, 10), isNull);
      expect(findContentRect(buf, 10, 10, threshold: 0), isNull);
    });
  });
}
