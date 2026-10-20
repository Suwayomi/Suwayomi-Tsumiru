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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/controller/reader_preview_channel.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/chrome/reader_color_overlays.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

/// Applies a 4x5 color matrix to an RGBA pixel (0..255 scale), like Skia.
List<double> _apply(List<double> m, List<double> p) => [
  for (var r = 0; r < 4; r++)
    m[r * 5] * p[0] +
        m[r * 5 + 1] * p[1] +
        m[r * 5 + 2] * p[2] +
        m[r * 5 + 3] * p[3] +
        m[r * 5 + 4],
];

/// Viewer stand-in that counts its own builds.
class _Probe extends StatefulWidget {
  const _Probe({required this.onBuild});

  final VoidCallback onBuild;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  Widget build(BuildContext context) {
    widget.onBuild();
    return const ColoredBox(color: Colors.white);
  }
}

void main() {
  setUp(() {
    readerBrightnessPreview.value = null;
    readerColorFilterPreview.value = null;
  });

  group('overlay math (Komikku parity)', () {
    test('brightness alpha = abs(value)/100 for negatives, clamped', () {
      expect(brightnessOverlayAlpha(-75), 0.75);
      expect(brightnessOverlayAlpha(-1), 0.01);
      expect(brightnessOverlayAlpha(-50), 0.5);
      expect(brightnessOverlayAlpha(-200), 1.0, reason: 'clamped');
      expect(applicationBrightnessFor(100), 1.0);
      expect(applicationBrightnessFor(50), 0.5);
      expect(applicationBrightnessFor(200), 1.0, reason: 'clamped');
      expect(applicationBrightnessFor(0), isNull);
      expect(applicationBrightnessFor(-50), isNull);
    });

    test('grayscale matrix = Android setSaturation(0) luminance weights', () {
      const white = <double>[255, 255, 255, 255];
      const red = <double>[255, 0, 0, 255];
      expect(_apply(kGrayscaleColorMatrix, white), [255, 255, 255, 255]);
      final gray = _apply(kGrayscaleColorMatrix, red);
      expect(gray[0], closeTo(0.213 * 255, 0.001));
      expect(gray[0], gray[1]);
      expect(gray[1], gray[2]);
      expect(gray[3], 255, reason: 'alpha untouched');
    });

    test('invert matrix = Komikku getCombinedPaint inversion', () {
      const white = <double>[255, 255, 255, 255];
      const black = <double>[0, 0, 0, 255];
      expect(_apply(kInvertColorMatrix, white), [0, 0, 0, 255]);
      expect(_apply(kInvertColorMatrix, black), [255, 255, 255, 255]);
    });
  });

  group('ReaderColorOverlays', () {
    Future<void> pumpOverlays(
      WidgetTester tester, {
      Map<String, Object> prefValues = const {},
      Widget? sibling,
    }) async {
      SharedPreferences.setMockInitialValues(prefValues);
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: MaterialApp(
            home: Stack(
              fit: StackFit.expand,
              children: [?sibling, const ReaderColorOverlays()],
            ),
          ),
        ),
      );
    }

    Finder inOverlays(Type type) => find.descendant(
      of: find.byType(ReaderColorOverlays),
      matching: find.byType(type),
    );

    Color? dimColor(WidgetTester tester) {
      final boxes = inOverlays(ColoredBox);
      if (boxes.evaluate().isEmpty) return null;
      return tester.widget<ColoredBox>(boxes.first).color;
    }

    testWidgets('committed -50 brightness → black dim at 0.5', (tester) async {
      await pumpOverlays(
        tester,
        prefValues: {'customBrightness': true, 'customBrightnessValue': -50},
      );
      final color = dimColor(tester);
      expect(color, isNotNull);
      expect(color!.a, closeTo(0.5, 0.005));
    });

    testWidgets('brightness draft overrides committed; clearing falls back', (
      tester,
    ) async {
      await pumpOverlays(
        tester,
        prefValues: {'customBrightness': true, 'customBrightnessValue': -20},
      );
      expect(dimColor(tester)!.a, closeTo(0.2, 0.005));

      readerBrightnessPreview.value = -75;
      await tester.pump();
      expect(dimColor(tester)!.a, closeTo(0.75, 0.005));

      readerBrightnessPreview.value = null;
      await tester.pump();
      expect(dimColor(tester)!.a, closeTo(0.2, 0.005));
    });
  });
}
