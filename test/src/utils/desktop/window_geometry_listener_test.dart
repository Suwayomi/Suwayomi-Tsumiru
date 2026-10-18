// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/utils/desktop/window_geometry_listener.dart';
import 'package:tsumiru/src/utils/desktop/window_geometry_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('window_manager');
  final calls = <String>[];
  var throwOnIsMaximized = false;

  setUp(() {
    calls.clear();
    throwOnIsMaximized = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          switch (call.method) {
            case 'isMaximized':
              if (throwOnIsMaximized) {
                throw PlatformException(code: 'unavailable');
              }
              return false;
            case 'getBounds':
              return <String, double>{
                'x': 0.0,
                'y': 0.0,
                'width': 800.0,
                'height': 600.0,
              };
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<WindowGeometryListener> newListener() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    return WindowGeometryListener(prefs);
  }

  test('close saves geometry before destroying', () async {
    final listener = await newListener();

    await listener.onWindowClose();

    expect(calls, ['isMaximized', 'getBounds', 'destroy']);
    final prefs = await SharedPreferences.getInstance();
    final geometry = loadWindowGeometry(prefs);
    expect(geometry.size, const Size(800, 600));
    expect(geometry.maximized, isFalse);
  });

  test(
    'close with a debounced save pending saves once, then destroys',
    () async {
      final listener = await newListener();
      listener.onWindowResize();

      await listener.onWindowClose();

      expect(calls, ['isMaximized', 'getBounds', 'destroy']);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(calls, ['isMaximized', 'getBounds', 'destroy']);
    },
  );

  test('close destroys even when the save throws', () async {
    throwOnIsMaximized = true;
    final listener = await newListener();

    await listener.onWindowClose();

    expect(calls, ['isMaximized', 'destroy']);
  });

  test('two close events destroy exactly once', () async {
    final listener = await newListener();

    await listener.onWindowClose();
    await listener.onWindowClose();

    expect(calls, ['isMaximized', 'getBounds', 'destroy']);
  });
}
