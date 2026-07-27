// The zoom prefs are per-viewer. A reader that still reads the pre-split
// global provider silently ignores its own switches — which is exactly what
// happened to the multi-chapter long-strip reader, because it lives in a
// subdirectory and a `reader_mode/*.dart` sweep missed it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _legacyProviders = [
  'pinchToZoomProvider',
  'doubleTapToZoomProvider',
  'disableZoomOutProvider',
];

/// Files allowed to mention the legacy providers: they are the migration
/// source, so the seeds and the settings-model entries still name them.
const _allowed = {
  'reader_zoom_toggles.dart',
  'reader_pinch_to_zoom.dart',
  'reader_settings_model.dart',
};

void main() {
  test('no reader engine reads the pre-split global zoom prefs', () {
    final readerModes = Directory(
      'lib/src/features/manga_book/presentation/reader/widgets/reader_mode',
    );
    expect(readerModes.existsSync(), isTrue,
        reason: 'reader_mode directory moved — update this test');

    final offenders = <String>[];
    for (final entity in readerModes.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (_allowed.contains(entity.uri.pathSegments.last)) continue;

      final source = entity.readAsStringSync();
      for (final provider in _legacyProviders) {
        if (source.contains(provider)) {
          offenders.add('${entity.path} -> $provider');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Use the paged*/longStrip* providers instead:\n'
          '${offenders.join('\n')}',
    );
  });
}
