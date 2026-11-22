// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_mode/infinity_continuous/tall_page_image.dart';

TallPagePlan? _plan(
  Size source, {
  double displayWidth = 400,
  double viewportHeight = 800,
  double devicePixelRatio = 2.5,
  int? textureLimit,
}) => tallPagePlan(
  source: source,
  displayWidth: displayWidth,
  viewportHeight: viewportHeight,
  devicePixelRatio: devicePixelRatio,
  textureLimit: textureLimit,
);

void main() {
  group('tallPagePlan', () {
    test('keeps pages up to two screens whole', () {
      // 1000px wide drawn at 400dp: two 800dp screens = 4000 source px.
      expect(_plan(const Size(1000, 4000)), isNull);
    });

    test('cuts longer pages into strips of at most two screens', () {
      final plan = _plan(const Size(1000, 30000))!;
      expect(plan.stripHeight, 4000);
      expect(plan.sampleSize, 1);
    });

    test('cuts even when the GPU has no texture limit', () {
      expect(_plan(const Size(1000, 30000)), isNotNull);
    });

    test('never exceeds the texture limit', () {
      final plan = _plan(const Size(1000, 30000), textureLimit: 2048)!;
      expect(plan.stripHeight, 2048);
      expect(_plan(const Size(1000, 3000), textureLimit: 2048), isNotNull);
    });

    test('downsamples sources much wider than the drawn width', () {
      // 400dp * 2.5 = 1000 device px; a 4000px source halves twice.
      final plan = _plan(const Size(4000, 60000))!;
      expect(plan.sampleSize, 4);
      expect(plan.stripHeight, tallPageMaxStripHeight);
    });

    test('rejects degenerate sizes', () {
      expect(_plan(Size.zero), isNull);
      expect(_plan(const Size(1000, 30000), viewportHeight: 0), isNull);
    });
  });

  test('tallPageDisplayWidth follows the scale mode', () {
    const source = Size(1000, 30000);
    expect(
      tallPageDisplayWidth(
        source: source,
        crossAxisExtent: 400,
        horizontal: false,
        naturalSize: false,
      ),
      400,
    );
    expect(
      tallPageDisplayWidth(
        source: source,
        crossAxisExtent: 2000,
        horizontal: false,
        naturalSize: true,
      ),
      1000,
    );
    expect(
      tallPageDisplayWidth(
        source: source,
        crossAxisExtent: 900,
        horizontal: true,
        naturalSize: false,
      ),
      30,
    );
  });
}
