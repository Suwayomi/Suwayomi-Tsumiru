// Splitting the three shared zoom prefs per viewer must not reset anyone's
// choice: an untouched viewer key falls back to the legacy global value, and
// once a viewer is set it stops tracking the other.

import 'dart:io';

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
    test('pinch, double tap and disable zoom out', () async {
      final c = await _containerWith({'pinchToZoom': false});
      addTearDown(c.dispose);

      expect(c.read(pagedPinchToZoomProvider), isFalse);
      expect(c.read(longStripPinchToZoomProvider), isFalse);

      // No reader engine may read the pre-split global zoom prefs.
      final legacyProviders = [
        RegExp(r'(?<![A-Za-z])pinchToZoomProvider\b'),
        RegExp(r'(?<![A-Za-z])doubleTapToZoomProvider\b'),
        RegExp(r'(?<![A-Za-z])disableZoomOutProvider\b'),
      ];
      final readerModes = Directory(
        'lib/src/features/manga_book/presentation/reader/widgets/reader_mode',
      );
      expect(
        readerModes.existsSync(),
        isTrue,
        reason: 'reader_mode directory moved — update this test',
      );
      final offenders = <String>[];
      for (final entity in readerModes.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = entity.readAsStringSync();
        for (final provider in legacyProviders) {
          final hit = provider.firstMatch(source);
          if (hit != null) {
            offenders.add('${entity.path} -> ${hit.group(0)}');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'Use the paged*/longStrip* providers instead:\n'
            '${offenders.join('\n')}',
      );

      final doubleTap = await _containerWith({'doubleTapToZoom': false});
      addTearDown(doubleTap.dispose);
      expect(doubleTap.read(pagedDoubleTapToZoomProvider), isFalse);
      expect(doubleTap.read(longStripDoubleTapToZoomProvider), isFalse);

      final zoomOut = await _containerWith({'disableZoomOut': true});
      addTearDown(zoomOut.dispose);
      expect(zoomOut.read(pagedDisableZoomOutProvider), isTrue);
      expect(zoomOut.read(longStripDisableZoomOutProvider), isTrue);
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
}
