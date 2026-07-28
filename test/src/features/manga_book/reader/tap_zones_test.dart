import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/utils/reader_mode_kind.dart';

void main() {
  group('Default resolves to a real layout', () {
    test('never resolves to Default or Disabled', () {
      for (final mode in ReaderMode.values) {
        final resolved = defaultNavigationFor(mode);
        expect(resolved, isNot(ReaderNavigationLayout.defaultNavigation),
            reason: '$mode');
        expect(resolved, isNot(ReaderNavigationLayout.disabled), reason: '$mode');
      }
    });

    test('horizontal paged gets right-and-left, everything else L-shaped', () {
      // Komikku: PagerConfig.defaultNavigation returns RightAndLeftNavigation
      // for horizontal pagers and LNavigation otherwise; WebtoonConfig always
      // returns LNavigation.
      const horizontal = [
        ReaderMode.singleHorizontalLTR,
        ReaderMode.singleHorizontalRTL,
        ReaderMode.continuousHorizontalLTR,
        ReaderMode.continuousHorizontalRTL,
      ];
      for (final mode in ReaderMode.values) {
        expect(
          defaultNavigationFor(mode),
          horizontal.contains(mode)
              ? ReaderNavigationLayout.rightAndLeft
              : ReaderNavigationLayout.lShaped,
          reason: '$mode',
        );
      }
    });
  });

  group('right-to-left mirrors the spatial layout', () {
    test('flipping horizontally toggles only the horizontal axis', () {
      expect(TapInvert.none.horizontallyFlipped, TapInvert.horizontal);
      expect(TapInvert.horizontal.horizontallyFlipped, TapInvert.none);
      expect(TapInvert.vertical.horizontallyFlipped, TapInvert.both);
      expect(TapInvert.both.horizontallyFlipped, TapInvert.vertical);
    });

    test('vertical inversion survives the flip', () {
      for (final invert in TapInvert.values) {
        expect(
          invert.horizontallyFlipped.invertsVertical,
          invert.invertsVertical,
          reason: '$invert',
        );
        expect(
          invert.horizontallyFlipped.invertsHorizontal,
          !invert.invertsHorizontal,
          reason: '$invert',
        );
      }
    });
  });

  group('display order', () {
    test('matches Komikku, and the stored order is left alone', () {
      expect(ReaderNavigationLayout.displayOrder, [
        ReaderNavigationLayout.defaultNavigation,
        ReaderNavigationLayout.lShaped,
        ReaderNavigationLayout.kindlish,
        ReaderNavigationLayout.edge,
        ReaderNavigationLayout.rightAndLeft,
        ReaderNavigationLayout.disabled,
      ]);
      // These persist by index — reordering the enum would silently move
      // everyone's saved setting to a different layout.
      expect(ReaderNavigationLayout.values, [
        ReaderNavigationLayout.defaultNavigation,
        ReaderNavigationLayout.lShaped,
        ReaderNavigationLayout.rightAndLeft,
        ReaderNavigationLayout.edge,
        ReaderNavigationLayout.kindlish,
        ReaderNavigationLayout.disabled,
      ]);
    });

    test('every layout is offered exactly once', () {
      expect(
        ReaderNavigationLayout.displayOrder.toSet(),
        ReaderNavigationLayout.values.toSet(),
      );
      expect(ReaderNavigationLayout.displayOrder.length,
          ReaderNavigationLayout.values.length);
    });
  });
}
