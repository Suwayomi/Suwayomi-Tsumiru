// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/utils/soft_clear_image_cache.dart';

Future<ui.Image> _decodeOnePixel() {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const ui.Rect.fromLTWH(0, 0, 1, 1),
    ui.Paint()..color = const ui.Color(0xFF000000),
  );
  return recorder.endRecording().toImage(1, 1);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> put(ImageCache cache, int key, ui.Image image) async {
    final completer = OneFrameImageStreamCompleter(
      Future.value(ImageInfo(image: image.clone())),
    );
    cache.putIfAbsent(key, () => completer);
    // Let the completer's future deliver so the entry lands in the cache.
    await Future<void>.delayed(Duration.zero);
  }

  test(
    'clear keeps the newest entries down to the floor, or empties fully',
    () async {
      final image = await _decodeOnePixel();
      final perImage = image.height * image.width * 4;
      final cache = SoftClearImageCache(floorBytes: perImage * 2)
        ..maximumSizeBytes = perImage * 10;
      for (var key = 0; key < 4; key++) {
        await put(cache, key, image);
      }
      expect(cache.currentSize, 4);

      cache.clear();

      // Floor holds the two most recent; budget is restored for new decodes.
      expect(cache.currentSize, 2);
      expect(cache.containsKey(3), isTrue);
      expect(cache.containsKey(2), isTrue);
      expect(cache.maximumSizeBytes, perImage * 10);

      // At or below the floor the clear empties fully.
      final tight = SoftClearImageCache(floorBytes: perImage * 10)
        ..maximumSizeBytes = perImage * 4;
      await put(tight, 1, image);
      expect(tight.currentSize, 1);
      tight.clear();
      expect(tight.currentSize, 0);
    },
  );
}
