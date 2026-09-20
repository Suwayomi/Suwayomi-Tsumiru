// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// "Show actions on long tap" wiring: with the pref ON a long-press on
// a reader page opens the page-actions sheet; with it OFF long-press is a
// no-op.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter_page/chapter_page_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_wrapper.dart';
import 'package:tsumiru/src/features/settings/presentation/reader/widgets/reader_general_prefs/reader_general_prefs.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

/// Forces [readWithLongTapProvider] to a fixed value without touching prefs.
class _FakeReadWithLongTap extends ReadWithLongTap {
  _FakeReadWithLongTap(this._value);
  final bool _value;
  @override
  bool? build() => _value;
}

ChapterPagesDto _pages() => ChapterPagesDto(
  chapter: ChapterPagesChapterDto(id: 1, pageCount: 3),
  pages: const [
    '/manga/1/chapter/0/page/0',
    '/manga/1/chapter/0/page/1',
    '/manga/1/chapter/0/page/2',
  ],
);

const _copyKey = ValueKey('reader-page-action-copy-image');
const _shareKey = ValueKey('reader-page-action-share');

Future<void> _pumpReader(
  WidgetTester tester, {
  required bool longTapOn,
  VoidCallback? onTap,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(const {});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        readWithLongTapProvider.overrideWith(
          () => _FakeReadWithLongTap(longTapOn),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ReaderView(
            toggleVisibility: onTap ?? () {},
            scrollDirection: Axis.vertical,
            mangaId: 1,
            readerScanlatorGroup: '',
            mangaReaderPadding: 0,
            onNext: () {},
            onPrevious: () {},
            prevNextChapterPair: null,
            mangaReaderNavigationLayout: ReaderNavigationLayout.disabled,
            readerSwipeChapterToggle: false,
            lastPageSwipeEnabled: false,
            resolvedReaderMode: ReaderMode.webtoon,
            currentIndex: 0,
            chapterPages: _pages(),
            child: const SizedBox.expand(child: ColoredBox(color: Colors.grey)),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('pref ON: long-press opens the page-actions sheet', (
    tester,
  ) async {
    await _pumpReader(tester, longTapOn: true);

    expect(find.byKey(_copyKey), findsNothing);

    await tester.longPress(find.byType(ReaderView));
    await tester.pumpAndSettle();

    // Sheet with the mobile actions is shown.
    expect(find.byKey(_copyKey), findsOneWidget);
    expect(find.byKey(_shareKey), findsOneWidget);
  });

  testWidgets('pref OFF: long-press is a no-op', (tester) async {
    await _pumpReader(tester, longTapOn: false);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ReaderView)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(find.byKey(_copyKey), findsNothing);

    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byKey(_copyKey), findsNothing);
  });

  // The reason the magnifier's removal mattered: a long-press recognizer that
  // consumes nothing still wins the gesture, and the tap that was meant to turn
  // the page is lost. Users reported having to tap twice.
  testWidgets('pref OFF: a slow tap still registers as a tap', (tester) async {
    var taps = 0;
    await _pumpReader(tester, longTapOn: false, onTap: () => taps++);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ReaderView)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(taps, 1);
  });
}
