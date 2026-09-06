// Regression guard for the iOS-only webtoon scroll freeze: vertical mode
// must not register the outer swipe recognizers that steal the single-finger
// drag from ZoomView (see multichapter_continuous_reader_mode.dart).

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter_page/chapter_page_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/directional_swipe_gesture_handler.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_gesture_state.dart';
import 'package:tsumiru/src/widgets/zoom/single_touch_drag_recognizers.dart';

/// Builds the REAL DirectionalSwipeGestureHandler for [axis] with the default
/// reader config (SIMPLE handler: swipeToggle on, lastPageSwipe off). It's a
/// HookConsumerWidget (reads readerIsZoomedInProvider), so callers must wrap
/// this in a ProviderScope.
DirectionalSwipeGestureHandler _realHandler(Axis axis) =>
    DirectionalSwipeGestureHandler(
      scrollDirection: axis,
      readerSwipeChapterToggle: true,
      lastPageSwipeEnabled: false,
      resolvedReaderMode: axis == Axis.vertical
          ? ReaderMode.webtoon
          : ReaderMode.singleHorizontalLTR,
      currentIndex: 0,
      chapterPages: ChapterPagesDto(
        chapter: ChapterPagesChapterDto(id: 1, pageCount: 3),
        pages: const ['a', 'b', 'c'],
      ),
      mangaId: 1,
      prevNextChapterPair: null,
      onTap: () {},
      onLongPressStart: (_) {},
      onNextPage: () {},
      onPreviousPage: () {},
      pageController: null,
      child: const SizedBox(width: 200, height: 400),
    );

/// True if any RawGestureDetector in the tree installs one of our SingleTouch*
/// swipe recognizers (the ones that steal the single-finger drag from ZoomView).
bool _hasSingleTouchRecognizer(WidgetTester tester) {
  return tester
      .widgetList<RawGestureDetector>(find.byType(RawGestureDetector))
      .any((r) => r.gestures.keys.any((t) =>
          t == SingleTouchPanGestureRecognizer ||
          t == SingleTouchHorizontalDragGestureRecognizer ||
          t == SingleTouchVerticalDragGestureRecognizer));
}

void main() {
  // REAL widget-level guard: pumps the actual DirectionalSwipeGestureHandler and
  // asserts it installs NONE of our SingleTouch* drag recognizers in vertical
  // mode (the fix) but DOES in horizontal mode.
  group('DirectionalSwipeGestureHandler vertical-mode recognizer guard', () {
    testWidgets('vertical mode installs NO SingleTouch* recognizer (the fix)',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(home: _realHandler(Axis.vertical)),
      ));
      expect(_hasSingleTouchRecognizer(tester), isFalse,
          reason: 'vertical mode must not register the swipe recognizers — they '
              'steal the single-finger drag from ZoomView and freeze iOS scroll');
    });
    testWidgets('horizontal mode DOES install a SingleTouch* recognizer',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(home: _realHandler(Axis.horizontal)),
      ));
      expect(_hasSingleTouchRecognizer(tester), isTrue,
          reason: 'horizontal/paged modes keep the swipe recognizers for '
              'chapter-boundary navigation');
    });
    testWidgets(
        'horizontal mode STILL installs a SingleTouch* recognizer while '
        'zoomed in — the widget tree must not change shape with zoom state '
        '(that would remount the page list); see '
        'single_touch_drag_recognizers_test.dart for the actual rejection '
        'behaviour', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(readerIsZoomedInProvider.notifier).state = true;

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: _realHandler(Axis.horizontal)),
      ));
      expect(_hasSingleTouchRecognizer(tester), isTrue,
          reason: 'zoom state must only change recognizer behaviour '
              '(self-rejection), never the widget tree shape');
    });
  });
}
