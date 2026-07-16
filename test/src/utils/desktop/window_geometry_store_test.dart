import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/utils/desktop/window_geometry.dart';
import 'package:tsumiru/src/utils/desktop/window_geometry_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('empty prefs load to a null-size, non-maximized geometry', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final g = loadWindowGeometry(prefs);
    expect(g.size, isNull);
    expect(g.maximized, isFalse);
  });

  test('wrong-typed stored keys degrade to defaults, not a throw', () async {
    SharedPreferences.setMockInitialValues({
      'window.width': 'corrupt',
      'window.height': true,
      'window.maximized': 1.5,
    });
    final prefs = await SharedPreferences.getInstance();
    final g = loadWindowGeometry(prefs);
    expect(g.size, isNull);
    expect(g.maximized, isFalse);
  });

  test('round-trips size + maximized', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await saveWindowGeometry(
        prefs, const WindowGeometry(size: Size(1024, 768), maximized: true));
    final g = loadWindowGeometry(prefs);
    expect(g.size, const Size(1024, 768));
    expect(g.maximized, isTrue);
  });
}
