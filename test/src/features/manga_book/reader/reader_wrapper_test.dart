// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter_page/chapter_page_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/controller/reader_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_wrapper.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

import 'reader_test_fixtures.dart';

void main() {
  testWidgets('prefetches adjacent paged chapters through retained listeners', (
    tester,
  ) async {
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
          getNextAndPreviousChaptersProvider(
            mangaId: 1,
            chapterId: 1,
          ).overrideWithValue((
            first: testChapter(id: 2, name: 'Chapter 2'),
            second: null,
          )),
          chapterProvider(chapterId: 2).overrideWithBuild((ref, _) {
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

  testWidgets(
    'long-strip next-zone tap scrolls the strip, falling back at the end',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues(const {});
      final prefs = await SharedPreferences.getInstance();

      var viewportForwardCalls = 0;
      var nextCalls = 0;
      var canScroll = true;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            getNextAndPreviousChaptersProvider(
              mangaId: 1,
              chapterId: 1,
            ).overrideWithValue((first: null, second: null)),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ReaderWrapper(
              manga: testManga().copyWith(
                meta: [
                  Fragment$MangaDto$meta(
                    key: 'flutter_readerNavigationLayout',
                    value: 'rightAndLeft',
                  ),
                ],
              ),
              chapter: testChapter(),
              chapterPages: ChapterPagesDto(
                chapter: ChapterPagesChapterDto(id: 1, pageCount: 3),
                pages: const ['a', 'b', 'c'],
              ),
              currentIndex: 0,
              onChanged: (_) {},
              onNext: () {
                nextCalls++;
              },
              onPrevious: () {},
              onViewportScrollForward: () {
                viewportForwardCalls++;
                return canScroll;
              },
              onViewportScrollBackward: () => false,
              scrollDirection: Axis.vertical,
              effectiveReaderMode: ReaderMode.webtoon,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);

      // Right third of the 800-wide screen, clear of the side seekbar and chrome bars.
      const nextZone = Offset(640, 800);
      await tester.tapAt(nextZone);
      await tester.pump();
      expect(viewportForwardCalls, 1);
      expect(nextCalls, 0);

      canScroll = false;
      await tester.tapAt(nextZone);
      await tester.pump();
      expect(viewportForwardCalls, 2);
      expect(nextCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
