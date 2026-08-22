// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tsumiru/src/features/manga_book/presentation/reader/crop/crop_isolate.dart';

/// PNG-encodes a [width]x[height] image: a solid [border] field with a solid
/// [fill] rectangle [rect] cut into it — [cropImageBytes] decodes real
/// encoded bytes (unlike [findContentRect], which takes raw RGBA directly).
Uint8List _encodedImage(
  int width,
  int height,
  img.Color border,
  ({int left, int top, int right, int bottom}) rect,
  img.Color fill,
) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: border);
  img.fillRect(
    image,
    x1: rect.left,
    y1: rect.top,
    x2: rect.right - 1,
    y2: rect.bottom - 1,
    color: fill,
  );
  return img.encodePng(image);
}

void main() {
  group('cropImageBytes', () {
    // 100x100 white field, red 80x80 content block (6% border each side —
    // comfortably past findContentRect's area guard).
    final rect = (left: 10, top: 10, right: 90, bottom: 90);
    late Uint8List encoded;

    setUp(() {
      encoded = _encodedImage(
        100,
        100,
        img.ColorRgb8(255, 255, 255),
        rect,
        img.ColorRgb8(255, 0, 0),
      );
    });

    test('no target size: crops without resizing', () async {
      final result = await cropImageBytes(encoded);
      expect(result, isNotNull);
      expect(result!.width, 80);
      expect(result.height, 80);
      // Every pixel of the cropped output is the red fill.
      for (var p = 0; p < result.rgba.length; p += 4) {
        expect(result.rgba[p], 255);
        expect(result.rgba[p + 1], 0);
        expect(result.rgba[p + 2], 0);
      }
    });

    test('targetWidth smaller than the crop downsizes it', () async {
      final result = await cropImageBytes(
        encoded,
        targetWidth: 40,
      );
      expect(result, isNotNull);
      expect(result!.width, 40);
      // Square content, single dimension given -> aspect preserved.
      expect(result.height, 40);
      expect(result.rgba.length, 40 * 40 * 4);
    });

    test('targetHeight smaller than the crop downsizes it', () async {
      final result = await cropImageBytes(
        encoded,
        targetHeight: 20,
      );
      expect(result, isNotNull);
      expect(result!.height, 20);
      expect(result.width, 20);
    });

    test('target size larger than the crop is left untouched (no upscale)',
        () async {
      final result = await cropImageBytes(
        encoded,
        targetWidth: 500,
        targetHeight: 500,
      );
      expect(result, isNotNull);
      expect(result!.width, 80);
      expect(result.height, 80);
    });

    test('no border found: still returns null with a target size set',
        () async {
      final uniform = img.Image(width: 20, height: 20);
      img.fill(uniform, color: img.ColorRgb8(255, 255, 255));
      final result = await cropImageBytes(
        img.encodePng(uniform),
        targetWidth: 10,
      );
      expect(result, isNull);
    });
  });
}
