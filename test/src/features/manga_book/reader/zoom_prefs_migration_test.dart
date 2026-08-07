// Splitting the three shared zoom prefs per viewer must not reset anyone's
// choice: an untouched viewer key falls back to the legacy global value, and
// once a viewer is set it stops tracking the other.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/settings/presentation/reader/widgets/reader_pinch_to_zoom/reader_pinch_to_zoom.dart';
import 'package:tsumiru/src/features/settings/presentation/reader/widgets/reader_zoom_toggles/reader_zoom_toggles.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

Future<ProviderContainer> _containerWith(Map<String, Object> stored) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
}

void main() {
  group('legacy value carries into both viewers', () {
    test('pinch to zoom', () async {
      final c = await _containerWith({'pinchToZoom': false});
      addTearDown(c.dispose);

      expect(c.read(pagedPinchToZoomProvider), isFalse);
      expect(c.read(longStripPinchToZoomProvider), isFalse);
    });

    test('double tap to zoom', () async {
      final c = await _containerWith({'doubleTapToZoom': false});
      addTearDown(c.dispose);

      expect(c.read(pagedDoubleTapToZoomProvider), isFalse);
      expect(c.read(longStripDoubleTapToZoomProvider), isFalse);
    });

    test('disable zoom out', () async {
      final c = await _containerWith({'disableZoomOut': true});
      addTearDown(c.dispose);

      expect(c.read(pagedDisableZoomOutProvider), isTrue);
      expect(c.read(longStripDisableZoomOutProvider), isTrue);
    });
  });

  test('a stored viewer value wins over the legacy one', () async {
    final c = await _containerWith({
      'pinchToZoom': true,
      'pagedPinchToZoom': false,
    });
    addTearDown(c.dispose);

    expect(c.read(pagedPinchToZoomProvider), isFalse);
    expect(c.read(longStripPinchToZoomProvider), isTrue);
  });

  test('setting one viewer leaves the other alone', () async {
    final c = await _containerWith({'pinchToZoom': true});
    addTearDown(c.dispose);

    expect(c.read(pagedPinchToZoomProvider), isTrue);
    expect(c.read(longStripPinchToZoomProvider), isTrue);

    c.read(pagedPinchToZoomProvider.notifier).update(false);

    expect(c.read(pagedPinchToZoomProvider), isFalse);
    expect(
      c.read(longStripPinchToZoomProvider),
      isTrue,
      reason: 'the two switches must stop moving together',
    );
  });
}
