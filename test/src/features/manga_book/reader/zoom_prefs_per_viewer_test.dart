// The zoom prefs are per-viewer. A reader that still reads the pre-split
// global provider silently ignores its own switches — which is exactly what
// happened to the multi-chapter long-strip reader, because it lives in a
// subdirectory and a `reader_mode/*.dart` sweep missed it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Word-anchored so `longStripDisableZoomOutProvider` is not mistaken for the
/// legacy `disableZoomOutProvider` it contains.
final _legacyProviders = [
  RegExp(r'(?<![A-Za-z])pinchToZoomProvider\b'),
  RegExp(r'(?<![A-Za-z])doubleTapToZoomProvider\b'),
  RegExp(r'(?<![A-Za-z])disableZoomOutProvider\b'),
];

void main() {
  test('no reader engine reads the pre-split global zoom prefs', () {
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
      for (final provider in _legacyProviders) {
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
  });
}
