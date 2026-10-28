// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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

const _captureKey = Key('capture');
const _pageGrey = Color(0xFF808080);
const _chromeGrey = Color(0xFF202020);

const _pageStack = RepaintBoundary(
  key: _captureKey,
  child: Stack(
    fit: StackFit.expand,
    children: [
      ColoredBox(color: _pageGrey),
      Positioned(
        left: 0,
        bottom: 0,
        width: 100,
        height: 60,
        child: ColoredBox(color: Colors.black),
      ),
      ReaderColorOverlays(),
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: SizedBox(height: 48, child: ColoredBox(color: _chromeGrey)),
      ),
    ],
  ),
);

const _screenBrightnessChannel = MethodChannel(
  'github.com/aaassseee/screen_brightness',
);

List<MethodCall> _recordScreenBrightnessCalls() {
  final calls = <MethodCall>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_screenBrightnessChannel, (call) async {
    calls.add(call);
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(_screenBrightnessChannel, null),
  );
  return calls;
}

Future<void> _pumpOverlays(
  WidgetTester tester, {
  required TargetPlatform platform,
  TargetPlatform? themePlatform,
  bool brightnessOn = false,
  int brightnessValue = 0,
}) async {
  debugDefaultTargetPlatformOverride = platform;
  await tester.pumpWidget(const SizedBox.shrink());
  SharedPreferences.setMockInitialValues({
    'customBrightness': brightnessOn,
    'customBrightnessValue': brightnessValue,
  });
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        theme: ThemeData(platform: themePlatform),
        home: _pageStack,
      ),
    ),
  );
  await tester.pump();
}

void _overlayTest(
  String description,
  Future<void> Function(WidgetTester tester) body, {
  bool skip = false,
}) {
  testWidgets(
    description,
    (tester) async {
      try {
        await body(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
    skip: skip,
  );
}

Future<List<int>> _pixelAt(WidgetTester tester, Offset position) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  late List<int> pixel;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final index = (position.dy.toInt() * image.width + position.dx.toInt()) * 4;
    pixel = [for (var i = 0; i < 4; i++) data!.getUint8(index + i)];
    image.dispose();
  });
  return pixel;
}

void _expectGrey(List<int> pixel, num grey, {num tolerance = 2}) {
  expect(pixel[0], closeTo(grey, tolerance));
  expect(pixel[1], closeTo(grey, tolerance));
  expect(pixel[2], closeTo(grey, tolerance));
  expect(pixel[3], 255);
}

void main() {
  tearDown(() {
    readerBrightnessPreview.value = null;
    readerColorFilterPreview.value = null;
  });

  test('overlay math matches Komikku: brightness, grayscale and invert', () {
    expect(brightnessOverlayAlpha(-75), 0.75);
    expect(brightnessOverlayAlpha(-1), 0.01);
    expect(brightnessOverlayAlpha(-50), 0.5);
    expect(brightnessOverlayAlpha(-200), 1.0, reason: 'clamped');
    expect(applicationBrightnessFor(100), 1.0);
    expect(applicationBrightnessFor(50), 0.5);
    expect(applicationBrightnessFor(200), 1.0, reason: 'clamped');
    expect(applicationBrightnessFor(0), isNull);
    expect(applicationBrightnessFor(-50), isNull);

    const white = <double>[255, 255, 255, 255];
    const red = <double>[255, 0, 0, 255];
    const black = <double>[0, 0, 0, 255];
    expect(_apply(kGrayscaleColorMatrix, white), [255, 255, 255, 255]);
    final gray = _apply(kGrayscaleColorMatrix, red);
    expect(gray[0], closeTo(0.213 * 255, 0.001));
    expect(gray[0], gray[1]);
    expect(gray[1], gray[2]);
    expect(gray[3], 255, reason: 'alpha untouched');

    expect(_apply(kInvertColorMatrix, white), [0, 0, 0, 255]);
    expect(_apply(kInvertColorMatrix, black), [255, 255, 255, 255]);

    expect(pageBrightnessFactor(0), 1.0);
    expect(pageBrightnessFactor(100), 2.0);
    expect(pageBrightnessFactor(-75), 0.25);
    expect(pageBrightnessFactor(-200), 0.0, reason: 'clamped');
    expect(_apply(brightnessColorMatrix(50), [100, 120, 200, 128]), [
      150,
      180,
      300,
      128,
    ]);
    expect(_apply(brightnessColorMatrix(100), black), black);
    final grayBright = _apply(
      pageBrightnessMatrix(value: 100, grayscale: true, inverted: false),
      red,
    );
    expect(grayBright[0], closeTo(0.213 * 255 * 2, 0.001));
    expect(grayBright[0], grayBright[1]);
    expect(grayBright[1], grayBright[2]);
  });

  _overlayTest('desktop brightness multiplies rendered page pixels', (
    tester,
  ) async {
    final calls = _recordScreenBrightnessCalls();

    // Theme overrides must not select native brightness.
    await _pumpOverlays(
      tester,
      platform: TargetPlatform.linux,
      themePlatform: TargetPlatform.android,
      brightnessOn: true,
      brightnessValue: 50,
    );
    _expectGrey(await _pixelAt(tester, const Offset(400, 300)), 192);
    _expectGrey(await _pixelAt(tester, const Offset(50, 570)), 0);
    _expectGrey(
      await _pixelAt(tester, const Offset(400, 10)),
      32,
      tolerance: 0,
    );

    readerBrightnessPreview.value = 25;
    await tester.pump();
    _expectGrey(await _pixelAt(tester, const Offset(400, 300)), 160);

    readerBrightnessPreview.value = null;
    await tester.pump();
    _expectGrey(await _pixelAt(tester, const Offset(400, 300)), 192);

    await _pumpOverlays(
      tester,
      platform: TargetPlatform.linux,
      brightnessOn: true,
      brightnessValue: -30,
    );
    _expectGrey(await _pixelAt(tester, const Offset(400, 300)), 90);
    _expectGrey(await _pixelAt(tester, const Offset(50, 570)), 0);

    await _pumpOverlays(
      tester,
      platform: TargetPlatform.linux,
      brightnessOn: false,
      brightnessValue: 50,
    );
    _expectGrey(await _pixelAt(tester, const Offset(400, 300)), 128);

    expect(calls, isEmpty, reason: 'desktop never calls the plugin');
  });

  _overlayTest('native platforms keep the OS override and reset it', (
    tester,
  ) async {
    final calls = _recordScreenBrightnessCalls();

    await _pumpOverlays(
      tester,
      platform: TargetPlatform.android,
      brightnessOn: true,
      brightnessValue: 50,
    );
    _expectGrey(await _pixelAt(tester, const Offset(400, 300)), 128);
    final set = calls.singleWhere(
      (call) => call.method == 'setApplicationScreenBrightness',
    );
    expect((set.arguments as Map)['brightness'], 0.5);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(
      calls.map((call) => call.method),
      contains('resetApplicationScreenBrightness'),
    );

    calls.clear();
    await _pumpOverlays(
      tester,
      platform: TargetPlatform.iOS,
      brightnessOn: true,
      brightnessValue: -50,
    );
    _expectGrey(await _pixelAt(tester, const Offset(400, 300)), 64);
    expect(
      calls.map((call) => call.method),
      isNot(contains('setApplicationScreenBrightness')),
    );
  }, skip: kIsWeb);
}
