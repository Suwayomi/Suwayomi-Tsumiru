// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Pure mappings: ReaderOrientation → platform orientations
// and TapInvert legacy-bool migration + axis truth table.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/settings/presentation/reader/widgets/reader_orientation/reader_orientation.dart';

void main() {
  group('ReaderOrientation.deviceOrientations', () {
    test('Default applies nothing (existing users see zero change)', () {
      expect(ReaderOrientation.defaultRotation.deviceOrientations, isNull);
    });

    test('locked mappings match Komikku', () {
      expect(ReaderOrientation.free.deviceOrientations,
          DeviceOrientation.values);
      expect(ReaderOrientation.portrait.deviceOrientations,
          [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
      expect(ReaderOrientation.landscape.deviceOrientations,
          [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      expect(ReaderOrientation.lockedPortrait.deviceOrientations,
          [DeviceOrientation.portraitUp]);
      expect(ReaderOrientation.lockedLandscape.deviceOrientations,
          [DeviceOrientation.landscapeLeft]);
      expect(ReaderOrientation.reversePortrait.deviceOrientations,
          [DeviceOrientation.portraitDown]);
    });

    test('7 values in Komikku chip order', () {
      expect(ReaderOrientation.values, const [
        ReaderOrientation.defaultRotation,
        ReaderOrientation.free,
        ReaderOrientation.portrait,
        ReaderOrientation.landscape,
        ReaderOrientation.lockedPortrait,
        ReaderOrientation.lockedLandscape,
        ReaderOrientation.reversePortrait,
      ]);
    });
  });

  group('TapInvert', () {
    test('legacy bool migration: true→both, false/null→none', () {
      expect(TapInvert.fromLegacyInvert(true), TapInvert.both);
      expect(TapInvert.fromLegacyInvert(false), TapInvert.none);
      expect(TapInvert.fromLegacyInvert(null), TapInvert.none);
    });

    test('axis truth table (Komikku TappingInvertMode)', () {
      expect(TapInvert.none.invertsHorizontal, isFalse);
      expect(TapInvert.none.invertsVertical, isFalse);
      expect(TapInvert.horizontal.invertsHorizontal, isTrue);
      expect(TapInvert.horizontal.invertsVertical, isFalse);
      expect(TapInvert.vertical.invertsHorizontal, isFalse);
      expect(TapInvert.vertical.invertsVertical, isTrue);
      expect(TapInvert.both.invertsHorizontal, isTrue);
      expect(TapInvert.both.invertsVertical, isTrue);
    });

    test('"both" equals the old bool-true full swap', () {
      // Old behavior swapped every zone; both must invert both axes so
      // migrated users notice nothing.
      final both = TapInvert.fromLegacyInvert(true);
      expect(both.invertsHorizontal && both.invertsVertical, isTrue);
    });
  });
}
