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
  bool smaller = false,
}) => tapActionForZone(
  position: Offset(x, y),
  size: _size,
  layout: layout,
  tapInvert: tapInvert,
  smallerTapZones: smaller,
);

void main() {
  group('Kindle-ish', () {
    // KindlishNavigation.kt: menu is the top third; below it, the left third
    // goes back and the remaining two thirds go forward.
    const layout = ReaderNavigationLayout.kindlish;

    test('menu is the top band, not the bottom', () {
      expect(_at(150, 50, layout: layout), TapAction.menu);
      expect(_at(150, 550, layout: layout), isNot(TapAction.menu));
    });

    test('below the menu band, left goes back and the rest forward', () {
      expect(_at(50, 400, layout: layout), TapAction.previous);
      expect(_at(150, 400, layout: layout), TapAction.next);
      expect(_at(280, 400, layout: layout), TapAction.next);
    });

    test('smaller tap zones shrink the menu band, growing the active area', () {
      // y = 180 is inside the default 200px menu band but outside the 150px one.
      expect(_at(150, 180, layout: layout), TapAction.menu);
      expect(
        _at(150, 180, layout: layout, smaller: true),
        isNot(TapAction.menu),
      );
    });
  });

  group('L-shaped', () {
    const layout = ReaderNavigationLayout.lShaped;

    test('top goes back, bottom goes forward', () {
      expect(_at(150, 50, layout: layout), TapAction.previous);
      expect(_at(150, 550, layout: layout), TapAction.next);
    });

    test('the middle band splits left, centre and right', () {
      expect(_at(50, 300, layout: layout), TapAction.previous);
      expect(_at(150, 300, layout: layout), TapAction.menu);
      expect(_at(280, 300, layout: layout), TapAction.next);
    });
  });

  group('Right and Left', () {
    const layout = ReaderNavigationLayout.rightAndLeft;

    test('edges page, the centre opens the menu', () {
      expect(_at(20, 300, layout: layout), TapAction.previous);
      expect(_at(280, 300, layout: layout), TapAction.next);
      expect(_at(150, 300, layout: layout), TapAction.menu);
    });

    test('horizontal inversion swaps the two edges', () {
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

  group('off', () {
    test('disabled and an unresolved default both just open the menu', () {
      for (final x in [20.0, 150.0, 280.0]) {
        for (final y in [20.0, 300.0, 580.0]) {
          expect(
            _at(x, y, layout: ReaderNavigationLayout.disabled),
            TapAction.menu,
          );
          expect(
            _at(x, y, layout: ReaderNavigationLayout.defaultNavigation),
            TapAction.menu,
          );
        }
      }
    });
  });
}
