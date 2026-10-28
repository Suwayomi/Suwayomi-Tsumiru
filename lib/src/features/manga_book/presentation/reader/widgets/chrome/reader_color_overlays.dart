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

double brightnessOverlayAlpha(int value) =>
    value < 0 ? (value.abs() / 100).clamp(0.0, 1.0) : 0.0;

double? applicationBrightnessFor(int value) =>
    value > 0 ? (value / 100).clamp(0.0, 1.0) : null;

bool isNativeScreenBrightnessPlatform(TargetPlatform platform) =>
    platform == TargetPlatform.android || platform == TargetPlatform.iOS;

bool usesPageBrightnessFor({
  required bool isWeb,
  required TargetPlatform platform,
}) => isWeb || !isNativeScreenBrightnessPlatform(platform);

bool _screenBrightnessSupportedFor(TargetPlatform platform) =>
    !kIsWeb && isNativeScreenBrightnessPlatform(platform);

double pageBrightnessFactor(int value) => (1 + value / 100).clamp(0.0, 2.0);

List<double> brightnessColorMatrix(int value) {
  final factor = pageBrightnessFactor(value);
  return [
    factor, 0, 0, 0, 0, //
    0, factor, 0, 0, 0, //
    0, 0, factor, 0, 0, //
    0, 0, 0, 1, 0,
  ];
}

List<double> pageBrightnessMatrix({
  required int value,
  required bool grayscale,
  required bool inverted,
}) {
  final brightness = brightnessColorMatrix(value);
  if (!grayscale && !inverted) return brightness;
  return composeColorMatrices(
    brightness,
    grayscaleInvertMatrix(grayscale: grayscale, inverted: inverted),
  );
}

/// Null resets window brightness; missing-plugin and permission errors are non-fatal.
Future<void> _applyScreenBrightness(
  double? target,
  TargetPlatform platform,
) async {
  if (!_screenBrightnessSupportedFor(platform)) return;
  try {
    if (target != null) {
      await ScreenBrightness.instance.setApplicationScreenBrightness(target);
    } else {
      await ScreenBrightness.instance.resetApplicationScreenBrightness();
    }
  } catch (_) {}
}

Future<void> _resetScreenBrightness(TargetPlatform platform) async {
  if (!_screenBrightnessSupportedFor(platform)) return;
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

    final platform = defaultTargetPlatform;
    final pageBrightness = usesPageBrightnessFor(
      isWeb: kIsWeb,
      platform: platform,
    );
    final brightnessOnPage = brightnessOn && pageBrightness;

    useEffect(() {
      void sync() {
        if (!_screenBrightnessSupportedFor(platform)) return;
        final value =
            brightnessOn ? (readerBrightnessPreview.value ?? brightness) : 0;
        _applyScreenBrightness(applicationBrightnessFor(value), platform);
      }

      sync();
      readerBrightnessPreview.addListener(sync);
      return () => readerBrightnessPreview.removeListener(sync);
    }, [brightnessOn, brightness, platform]);

    // Reader teardown → drop the override so it never leaks app-wide.
    useEffect(() => () => _resetScreenBrightness(platform), [platform]);

    final filtersOn = grayscale || inverted;

    if (!filtersOn && !brightnessOn && !colorFilterOn) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (filtersOn || brightnessOnPage)
            _PageFilterOverlay(
              grayscale: grayscale,
              inverted: inverted,
              brightnessOn: brightnessOnPage,
              committed: brightness,
            ),
          if (brightnessOn && !pageBrightness)
            _BrightnessOverlay(committed: brightness),
          if (colorFilterOn)
            _ColorFilterOverlay(committed: color, blend: blend),
        ],
      ),
    );
  }
}

class _PageFilterOverlay extends StatelessWidget {
  const _PageFilterOverlay({
    required this.grayscale,
    required this.inverted,
    required this.brightnessOn,
    required this.committed,
  });

  final bool grayscale;
  final bool inverted;
  final bool brightnessOn;
  final int committed;

  @override
  Widget build(BuildContext context) {
    if (!brightnessOn) {
      return _BackdropOverlay(
        filter: ColorFilter.matrix(
          grayscaleInvertMatrix(grayscale: grayscale, inverted: inverted),
        ),
      );
    }
    return ValueListenableBuilder<int?>(
      valueListenable: readerBrightnessPreview,
      builder: (context, draft, _) {
        final value = draft ?? committed;
        if (!grayscale && !inverted && value == 0) {
          return const SizedBox.shrink();
        }
        return _BackdropOverlay(
          filter: ColorFilter.matrix(
            pageBrightnessMatrix(
              value: value,
              grayscale: grayscale,
              inverted: inverted,
            ),
          ),
        );
      },
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
