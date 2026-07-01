// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../constants/db_keys.dart';
import '../../../../../../constants/enum.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../settings/presentation/reader/widgets/reader_filter_prefs/reader_filter_prefs.dart';
import '../../controller/reader_preview_channel.dart';

/// Komikku setCustomBrightnessValue: negatives dim via a black overlay at
/// abs(value)/100 (-75 → 0.75); 0 and positives draw nothing (positive =
/// Android window brightness attr, inert here).
double brightnessOverlayAlpha(int value) =>
    value < 0 ? (value.abs() / 100).clamp(0.0, 1.0) : 0.0;

/// Android ColorMatrix.setSaturation(0) — Komikku's grayscale paint.
const List<double> kGrayscaleColorMatrix = [
  0.213, 0.715, 0.072, 0, 0, //
  0.213, 0.715, 0.072, 0, 0, //
  0.213, 0.715, 0.072, 0, 0, //
  0, 0, 0, 1, 0,
];

/// Komikku getCombinedPaint's inversion matrix.
const List<double> kInvertColorMatrix = [
  -1, 0, 0, 0, 255, //
  0, -1, 0, 0, 255, //
  0, 0, -1, 0, 255, //
  0, 0, 0, 1, 0,
];

/// 4x5 color-matrix concat: [inner] applies first, then [outer]
/// (Android postConcat semantics).
List<double> composeColorMatrices(List<double> outer, List<double> inner) {
  final result = List<double>.filled(20, 0);
  for (var row = 0; row < 4; row++) {
    for (var col = 0; col < 5; col++) {
      var v = col == 4 ? outer[row * 5 + 4] : 0.0;
      for (var k = 0; k < 4; k++) {
        v += outer[row * 5 + k] * inner[k * 5 + col];
      }
      result[row * 5 + col] = v;
    }
  }
  return result;
}

/// The matrix for the active grayscale/invert combination; grayscale applies
/// first when both are on, matching Komikku's getCombinedPaint.
List<double> grayscaleInvertMatrix({
  required bool grayscale,
  required bool inverted,
}) {
  if (grayscale && inverted) {
    return composeColorMatrices(kInvertColorMatrix, kGrayscaleColorMatrix);
  }
  return inverted ? kInvertColorMatrix : kGrayscaleColorMatrix;
}

/// Custom-filter overlays (design §2.4 layer 3): leaf siblings of the viewer
/// in the ReaderChrome Stack, below the flash overlay and the chrome bars so
/// only the page content beneath gets tinted.
///
/// Grayscale/invert and the blended color filter use [BackdropFilter] — a
/// leaf [ColorFiltered] only filters its own child, never the pixels below.
/// Each overlay listens to `draft ?? committed`, so slider drags repaint just
/// this subtree.
class ReaderColorOverlays extends ConsumerWidget {
  const ReaderColorOverlays({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grayscale = ref.watch(grayscaleProvider).ifNull(false);
    final inverted = ref.watch(invertedColorsProvider).ifNull(false);
    final brightnessOn = ref.watch(customBrightnessProvider).ifNull(false);
    final brightness = ref.watch(customBrightnessValueProvider) ??
        DBKeys.customBrightnessValue.initial as int;
    final colorFilterOn = ref.watch(customColorFilterProvider).ifNull(false);
    final color = ref.watch(colorFilterValueProvider) ??
        DBKeys.colorFilterValue.initial as int;
    final blend = ref.watch(colorFilterBlendModeKeyProvider) ??
        DBKeys.colorFilterBlendMode.initial as ColorFilterBlendMode;

    if (!grayscale && !inverted && !brightnessOn && !colorFilterOn) {
      return const SizedBox.shrink();
    }

    // Komikku paint order: matrix on the viewer layer, brightness dim on top,
    // then the blended color rect.
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (grayscale || inverted)
            _BackdropOverlay(
              filter: ColorFilter.matrix(
                grayscaleInvertMatrix(grayscale: grayscale, inverted: inverted),
              ),
            ),
          if (brightnessOn) _BrightnessOverlay(committed: brightness),
          if (colorFilterOn)
            _ColorFilterOverlay(committed: color, blend: blend),
        ],
      ),
    );
  }
}

/// Semi-transparent black dim for negative custom-brightness values.
class _BrightnessOverlay extends StatelessWidget {
  const _BrightnessOverlay({required this.committed});

  final int committed;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int?>(
      valueListenable: readerBrightnessPreview,
      builder: (context, draft, _) {
        final alpha = brightnessOverlayAlpha(draft ?? committed);
        if (alpha == 0) return const SizedBox.shrink();
        return RepaintBoundary(
          child: ColoredBox(color: Colors.black.withValues(alpha: alpha)),
        );
      },
    );
  }
}

/// ARGB color blended over the page (Komikku drawRect(color, blendMode)).
class _ColorFilterOverlay extends StatelessWidget {
  const _ColorFilterOverlay({required this.committed, required this.blend});

  final int committed;
  final ColorFilterBlendMode blend;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int?>(
      valueListenable: readerColorFilterPreview,
      builder: (context, draft, _) => _BackdropOverlay(
        filter: ColorFilter.mode(Color(draft ?? committed), blend.blendMode),
      ),
    );
  }
}

class _BackdropOverlay extends StatelessWidget {
  const _BackdropOverlay({required this.filter});

  final ColorFilter filter;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ClipRect(
        child: BackdropFilter(
          filter: filter,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}
