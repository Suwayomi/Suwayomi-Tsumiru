// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter_page/chapter_page_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/controller/reader_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_wrapper.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

import 'reader_test_fixtures.dart';

void main() {
  testWidgets('mounts without changing providers during build', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          getNextAndPreviousChaptersProvider(mangaId: 1, chapterId: 1)
              .overrideWithValue(null),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ReaderWrapper(
            manga: testManga(),
            chapter: testChapter(),
            chapterPages: ChapterPagesDto(
              chapter: ChapterPagesChapterDto(id: 1, pageCount: 3),
              pages: const ['a', 'b', 'c'],
            ),
            currentIndex: 0,
            onChanged: (_) {},
            onNext: () {},
            onPrevious: () {},
            scrollDirection: Axis.horizontal,
            effectiveReaderMode: ReaderMode.singleHorizontalLTR,
            child: const SizedBox.shrink(),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('prefetches adjacent paged chapters through retained listeners',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    var chapterFetches = 0;
    var pageFetches = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          getNextAndPreviousChaptersProvider(mangaId: 1, chapterId: 1)
              .overrideWithValue(
            (first: testChapter(id: 2, name: 'Chapter 2'), second: null),
          ),
          chapterProvider(chapterId: 2).overrideWith((ref) {
            chapterFetches += 1;
            return testChapter(id: 2, name: 'Chapter 2');
          }),
          chapterPagesProvider(chapterId: 2).overrideWith((ref) {
            pageFetches += 1;
            return ChapterPagesDto(
              chapter: ChapterPagesChapterDto(id: 2, pageCount: 3),
              pages: const ['d', 'e', 'f'],
            );
          }),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ReaderWrapper(
            manga: testManga(),
            chapter: testChapter(),
            chapterPages: ChapterPagesDto(
              chapter: ChapterPagesChapterDto(id: 1, pageCount: 3),
              pages: const ['a', 'b', 'c'],
            ),
            currentIndex: 2,
            onChanged: (_) {},
            onNext: () {},
            onPrevious: () {},
            scrollDirection: Axis.horizontal,
            effectiveReaderMode: ReaderMode.singleHorizontalLTR,
            child: const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(chapterFetches, 1);
    expect(pageFetches, 1);
  });
}
