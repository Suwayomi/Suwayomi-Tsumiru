// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// With "Ignore safe area" on, the page draws under side insets (iPhone Duo's
// cover-screen status column, a notch in landscape), so the reader chrome has
// to keep its controls out of them while its bars still run to the edge.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter_page/chapter_page_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/controller/reader_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/brand_page_seekbar.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/chrome/reader_bottom_controls.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/chrome/reader_chrome.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/chrome/reader_side_seekbar.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/chrome/reader_top_bar.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/chrome/reader_utils_bar.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

import 'reader_test_fixtures.dart';

// iPhone Duo's outer display, closed and upright: the status bar and camera
// take a full-height column down the right edge.
const _window = Size(466, 678);
const _column = 84.0;

Future<void> _pumpChrome(
  WidgetTester tester, {
  required EdgeInsets insets,
  bool useBottomSeekBar = false,
  bool showSideSeekBar = true,
  Map<String, Object> prefValues = const {},
}) async {
  tester.view.physicalSize = _window;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(prefValues);
  final prefs = await SharedPreferences.getInstance();
  final visibility = ValueNotifier(true);
  addTearDown(visibility.dispose);
  final utilsBarExpanded = ValueNotifier(true);
  addTearDown(utilsBarExpanded.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        chapterProvider(chapterId: 1).overrideWithBuild(
          (ref, _) => testChapter(),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            // What the reader sees with "Ignore safe area" on: nothing above
            // it has applied the insets.
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(padding: insets, viewPadding: insets),
              child: ReaderChrome(
                manga: testManga(),
                chapter: testChapter(),
                chapterPages: ChapterPagesDto(
                  chapter: ChapterPagesChapterDto(id: 1, pageCount: 3),
                  pages: const ['a', 'b', 'c'],
                ),
                currentIndex: 0,
                totalPageCount: null,
                visibility: visibility,
                utilsBarExpanded: utilsBarExpanded,
                useBottomSeekBar: useBottomSeekBar,
                showSideSeekBar: showSideSeekBar,
                scrollDirection: Axis.vertical,
                onPreviousChapter: () {},
                onNextChapter: () {},
                resolvedReaderMode: ReaderMode.webtoon,
                autoScrollSupported: true,
                reverseSeekBar: false,
                onChanged: (_) {},
                onOpenSettings: () {},
                onOpenReaderMode: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  // Let the chrome measure its bars and settle the side seek bar.
  await tester.pumpAndSettle();
}

/// Every control the chrome shows: buttons and seek bars.
Iterable<Rect> _controlRects(WidgetTester tester) => [
  ...find.byType(IconButton).evaluate(),
  ...find.byType(BrandPageSeekBar).evaluate(),
].map((element) {
  final box = element.renderObject! as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
});

void _expectClear(WidgetTester tester, {double left = 0, double right = 0}) {
  final rects = _controlRects(tester).toList();
  expect(rects, isNotEmpty);
  for (final rect in rects) {
    expect(rect.left, greaterThanOrEqualTo(left - 0.01), reason: '$rect');
    expect(
      rect.right,
      lessThanOrEqualTo(_window.width - right + 0.01),
      reason: '$rect',
    );
  }
}

Rect _barBackground<T extends Widget>(WidgetTester tester) => tester.getRect(
  find.descendant(of: find.byType(T), matching: find.byType(Material)).first,
);

void main() {
  testWidgets('controls stay out of a right side column', (tester) async {
    await _pumpChrome(
      tester,
      insets: const EdgeInsets.only(right: _column),
    );

    _expectClear(tester, right: _column);
    // The side seek bar keeps its 6 pt gap from the column, not the screen.
    expect(
      tester.getRect(find.byType(ReaderSideSeekBar)).right,
      _window.width - _column - 6,
    );
  });

  testWidgets('bar backgrounds still run under the column', (tester) async {
    await _pumpChrome(
      tester,
      insets: const EdgeInsets.only(right: _column),
    );

    for (final rect in [
      _barBackground<ReaderTopBar>(tester),
      _barBackground<ReaderUtilsBar>(tester),
      tester.getRect(
        find
            .descendant(
              of: find.byType(ReaderBottomControls),
              matching: find.byType(Card),
            )
            .last,
      ),
    ]) {
      expect(rect.left, 0);
      expect(rect.right, _window.width);
    }
  });

  testWidgets('bottom seek bar row stays out of the column', (tester) async {
    await _pumpChrome(
      tester,
      insets: const EdgeInsets.only(right: _column),
      useBottomSeekBar: true,
      showSideSeekBar: false,
    );

    expect(find.byType(BrandPageSeekBar), findsOneWidget);
    _expectClear(tester, right: _column);
  });

  testWidgets('left-handed side seek bar clears a left inset', (
    tester,
  ) async {
    await _pumpChrome(
      tester,
      insets: const EdgeInsets.symmetric(horizontal: 59),
      prefValues: const {'leftHandedVerticalSeekbar': true},
    );

    _expectClear(tester, left: 59, right: 59);
    expect(tester.getRect(find.byType(ReaderSideSeekBar)).left, 59 + 6);
  });

  testWidgets('no side insets leaves the layout as it was', (tester) async {
    await _pumpChrome(tester, insets: EdgeInsets.zero);

    expect(
      tester.getRect(find.byType(ReaderSideSeekBar)).right,
      _window.width - 6,
    );
    final controls = _controlRects(tester).toList();
    expect(
      controls.map((rect) => rect.right).reduce((a, b) => a > b ? a : b),
      greaterThan(_window.width - _column),
    );
  });
}
