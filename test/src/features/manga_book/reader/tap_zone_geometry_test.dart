// Pins tapActionForZone's geometry against the overlay it's meant to match.
// Komikku's edge band: 1/3 of the axis, or 1/4 with smaller tap zones on.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_mode/paged_reader_viewport.dart';

const _size = Size(300, 600);

TapAction _at(
  double x,
  double y, {
  required ReaderNavigationLayout layout,
  TapInvert tapInvert = TapInvert.none,
}) => tapActionForZone(
  position: Offset(x, y),
  size: _size,
  layout: layout,
  tapInvert: tapInvert,
  smallerTapZones: false,
);

void main() {
  group('Right and Left', () {
    const layout = ReaderNavigationLayout.rightAndLeft;

    test('edges page, centre opens the menu, inversion swaps the edges', () {
      expect(_at(20, 300, layout: layout), TapAction.previous);
      expect(_at(280, 300, layout: layout), TapAction.next);
      expect(_at(150, 300, layout: layout), TapAction.menu);

      expect(
        _at(20, 300, layout: layout, tapInvert: TapInvert.horizontal),
        TapAction.next,
      );
      expect(
        _at(280, 300, layout: layout, tapInvert: TapInvert.horizontal),
        TapAction.previous,
      );
    });
  });
}
