// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// "Show page number": a subtle "n / m" pill in the reader chrome.
// It is an always-mounted leaf gated ONLY by the pref (not the chrome
// animation), so it stays visible while reading (chrome hidden), shows
// "currentPage / totalPages", and disappears when the pref is OFF.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter_page/chapter_page_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/controller/reader_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/chrome/reader_chrome.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

MangaDto _manga() => Fragment$MangaDto(
  id: 1,
  title: 'Test Manga',
  chapters: Fragment$MangaDto$chapters(totalCount: 0),
  genre: const [],
  initialized: true,
  meta: const [],
  sourceId: '1',
  status: Enum$MangaStatus.ONGOING,
  categories: Fragment$MangaDto$categories(nodes: const []),
  trackRecords: Fragment$MangaDto$trackRecords(nodes: const []),
  updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
  url: '/manga/1',
  user: Fragment$MangaDto$user(
    bookmarkCount: 0,
    downloadCount: 0,
    inLibrary: true,
    inLibraryAt: '0',
    unreadCount: 0,
  ),
);

ChapterDto _chapter() => Fragment$ChapterDto(
  chapterNumber: 1,
  fetchedAt: '0',
  id: 1,
  mangaId: 1,
  name: 'Chapter 1',
  pageCount: 3,
  sourceOrder: 1,
  uploadDate: '0',
  url: '/chapter/1',
  meta: const [],
  user: Fragment$ChapterDto$user(
    isBookmarked: false,
    isDownloaded: false,
    isRead: false,
    lastPageRead: 0,
    lastReadAt: '0',
  ),
);

Future<void> _pumpChrome(
  WidgetTester tester, {
  Map<String, Object> prefValues = const {},
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(prefValues);
  final prefs = await SharedPreferences.getInstance();
  final visibility = ValueNotifier(true);
  addTearDown(visibility.dispose);
  final utilsBarExpanded = ValueNotifier(false);
  addTearDown(utilsBarExpanded.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        chapterProvider(chapterId: 1).overrideWithBuild((ref, _) => _chapter()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ReaderChrome(
            manga: _manga(),
            chapter: _chapter(),
            chapterPages: ChapterPagesDto(
              chapter: ChapterPagesChapterDto(id: 1, pageCount: 3),
              pages: const ['a', 'b', 'c'],
            ),
            currentIndex: 0,
            totalPageCount: null,
            visibility: visibility,
            utilsBarExpanded: utilsBarExpanded,
            useBottomSeekBar: true,
            showSideSeekBar: false,
            scrollDirection: Axis.horizontal,
            onPreviousChapter: null,
            onNextChapter: null,
            resolvedReaderMode: ReaderMode.singleHorizontalLTR,
            autoScrollSupported: false,
            reverseSeekBar: false,
            onChanged: (_) {},
            onOpenSettings: () {},
            onOpenReaderMode: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('page-number indicator', () {
    testWidgets('pref OFF hides the indicator', (tester) async {
      await _pumpChrome(tester, prefValues: const {'showPageNumber': false});
      expect(find.text('1 / 3'), findsNothing);
    });
  });
}
