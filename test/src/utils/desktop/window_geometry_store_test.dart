import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/utils/desktop/window_geometry.dart';
import 'package:tsumiru/src/utils/desktop/window_geometry_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads defaults from empty or corrupt prefs without throwing', () async {
    SharedPreferences.setMockInitialValues({});
    var prefs = await SharedPreferences.getInstance();
    var g = loadWindowGeometry(prefs);
    expect(g.size, isNull);
    expect(g.maximized, isFalse);

    SharedPreferences.setMockInitialValues({
      'window.width': 'corrupt',
      'window.height': true,
      'window.maximized': 1.5,
    });
    prefs = await SharedPreferences.getInstance();
    g = loadWindowGeometry(prefs);
    expect(g.size, isNull);
    expect(g.maximized, isFalse);
  });

  test('round-trips size + maximized', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await saveWindowGeometry(
      prefs,
      const WindowGeometry(size: Size(1024, 768), maximized: true),
    );
    final g = loadWindowGeometry(prefs);
    expect(g.size, const Size(1024, 768));
    expect(g.maximized, isTrue);
  });
}
