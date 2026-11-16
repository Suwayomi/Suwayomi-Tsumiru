// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/utils/cover_decode_image.dart';

/// Fails every load, like a cover fetch while the server is unreachable.
class _FailingImage extends ImageProvider<_FailingImage> {
  const _FailingImage();

  @override
  Future<_FailingImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_FailingImage>(this);

  @override
  ImageStreamCompleter loadImage(
    _FailingImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(
    Future<ImageInfo>.error(StateError('server unreachable')),
  );
}

void main() {
  group('coverDecodeSize', () {
    // A 2:3 tile, 400 × 600 physical pixels.
    const boxW = 400, boxH = 600;

    test('a wide cover decodes to the tile height, not the tile width', () {
      // 16:9 banner: width-only capping gave 400 × 225, enlarged 2.7× to fill.
      final size = coverDecodeSize(1600, 900, boxW, boxH)!;
      expect(size.height, boxH);
      expect(size.width, greaterThanOrEqualTo(boxW));
      expect(size.width, 1067);
    });

    test('a tall cover decodes to the tile width', () {
      final size = coverDecodeSize(1000, 2000, boxW, boxH)!;
      expect(size.width, boxW);
      expect(size.height, greaterThanOrEqualTo(boxH));
    });

    test('a cover the shape of the tile decodes to the tile', () {
      final size = coverDecodeSize(2000, 3000, boxW, boxH)!;
      expect(size.width, boxW);
      expect(size.height, boxH);
    });

    test('both sides always cover the tile', () {
      for (final (w, h) in [(800, 450), (1960, 1960), (2894, 4093), (640, 4000)]) {
        final size = coverDecodeSize(w, h, boxW, boxH);
        if (size == null) continue;
        expect(size.width, greaterThanOrEqualTo(boxW), reason: '$w × $h');
        expect(size.height, greaterThanOrEqualTo(boxH), reason: '$w × $h');
      }
    });

    test('a cover already smaller than the tile is never scaled up', () {
      // 800 × 450 needs 1067 × 600 to cover; it stays at its own size.
      expect(coverDecodeSize(800, 450, boxW, boxH), isNull);
      expect(coverDecodeSize(300, 450, boxW, boxH), isNull);
    });

    test('an empty image size is left alone', () {
      expect(coverDecodeSize(0, 0, boxW, boxH), isNull);
    });
  });

  group('CoverDecodeImage', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test('a failed load leaves the image cache, so it can be fetched again', () async {
      const provider = CoverDecodeImage(_FailingImage(), width: 40, height: 60);
      final key = await provider.obtainKey(ImageConfiguration.empty);
      final failed = Completer<void>();
      provider
          .resolve(ImageConfiguration.empty)
          .addListener(
            ImageStreamListener(
              (_, _) {},
              onError: (_, _) {
                if (!failed.isCompleted) failed.complete();
              },
            ),
          );
      await failed.future;
      // Eviction runs in a microtask after the error.
      await Future<void>.delayed(Duration.zero);
      expect(PaintingBinding.instance.imageCache.containsKey(key), isFalse);
    });

    test('keys differ per decode size and match for the same size', () async {
      const a = CoverDecodeImage(_FailingImage(), width: 40, height: 60);
      const b = CoverDecodeImage(_FailingImage(), width: 40, height: 60);
      const c = CoverDecodeImage(_FailingImage(), width: 40, height: 80);
      final ka = await a.obtainKey(ImageConfiguration.empty);
      expect(await b.obtainKey(ImageConfiguration.empty), ka);
      expect(await c.obtainKey(ImageConfiguration.empty), isNot(ka));
    });
  });
}
