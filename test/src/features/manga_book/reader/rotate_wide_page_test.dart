// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Rotate-wide contract: a landscape page gets a
// +90° quarter turn (-90° inverted); a portrait page renders untouched.

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_mode/rotate_wide_page.dart';

Future<ui.Image> _rasterImage(int width, int height) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder);
  return recorder.endRecording().toImage(width, height);
}

/// Delivers a pre-decoded image synchronously, like a cache-hit provider.
class _TestImageProvider extends ImageProvider<_TestImageProvider> {
  _TestImageProvider(this.image);

  final ui.Image image;

  @override
  Future<_TestImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _TestImageProvider key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(
    SynchronousFuture(ImageInfo(image: image.clone())),
  );
}

void main() {
  Future<void> pumpPage(
    WidgetTester tester, {
    required int width,
    required int height,
  }) async {
    final image = await _rasterImage(width, height);
    addTearDown(image.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: RotateWidePage(
          imageProvider: _TestImageProvider(image),
          invert: false,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('wide image is rotated a quarter turn clockwise', (tester) async {
    await pumpPage(tester, width: 200, height: 100);

    final rotated = tester.widget<RotatedBox>(find.byType(RotatedBox));
    expect(rotated.quarterTurns, 1);
  });
}
