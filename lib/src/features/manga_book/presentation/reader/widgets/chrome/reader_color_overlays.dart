// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../../../../../../constants/db_keys.dart';
import '../../../../../../constants/enum.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../settings/presentation/reader/widgets/reader_filter_prefs/reader_filter_prefs.dart';
import '../../controller/reader_preview_channel.dart';

/// Negative values dim with black at abs(value)/100; positive values change window brightness.
double brightnessOverlayAlpha(int value) =>
    value < 0 ? (value.abs() / 100).clamp(0.0, 1.0) : 0.0;

/// Positive values map to window brightness 0..1; zero/negative reset to system brightness.
double? applicationBrightnessFor(int value) =>
    value > 0 ? (value / 100).clamp(0.0, 1.0) : null;

/// screen_brightness ships only Android/iOS/macOS/Windows; elsewhere no-op.
bool get _screenBrightnessSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows);

/// Null resets window brightness; missing-plugin and permission errors are non-fatal.
Future<void> _applyScreenBrightness(double? target) async {
  if (!_screenBrightnessSupported) return;
  try {
    if (target != null) {
      await ScreenBrightness.instance.setApplicationScreenBrightness(target);
    } else {
      await ScreenBrightness.instance.resetApplicationScreenBrightness();
    }
  } catch (_) {}
}

Future<void> _resetScreenBrightness() async {
  if (!_screenBrightnessSupported) return;
  try {
    await ScreenBrightness.instance.resetApplicationScreenBrightness();
  } catch (_) {}
}

/// Android ColorMatrix.setSaturation(0) — the grayscale paint.
const List<double> kGrayscaleColorMatrix = [
  0.213, 0.715, 0.072, 0, 0, //
  0.213, 0.715, 0.072, 0, 0, //
  0.213, 0.715, 0.072, 0, 0, //
  0, 0, 0, 1, 0,
];

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
/// first when both are on.
List<double> grayscaleInvertMatrix({
  required bool grayscale,
  required bool inverted,
}) {
  if (grayscale && inverted) {
    return composeColorMatrices(kInvertColorMatrix, kGrayscaleColorMatrix);
  }
  return inverted ? kInvertColorMatrix : kGrayscaleColorMatrix;
}

/// BackdropFilter affects pages underneath; leaf ColorFiltered would only affect its child.
class ReaderColorOverlays extends HookConsumerWidget {
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

    // Listen to brightness drafts without rebuilding; reset when disabled or nonpositive.
    useEffect(() {
      void sync() {
        final value =
            brightnessOn ? (readerBrightnessPreview.value ?? brightness) : 0;
        _applyScreenBrightness(applicationBrightnessFor(value));
      }

      sync();
      readerBrightnessPreview.addListener(sync);
      return () => readerBrightnessPreview.removeListener(sync);
    }, [brightnessOn, brightness]);

    // Reader teardown → drop the override so it never leaks app-wide.
    useEffect(() => _resetScreenBrightness, const []);

    if (!grayscale && !inverted && !brightnessOn && !colorFilterOn) {
      return const SizedBox.shrink();
    }

    // Paint order: matrix on the viewer layer, brightness dim on top,
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
