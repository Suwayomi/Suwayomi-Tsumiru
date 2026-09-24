// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// The strip draws edge to edge, so the last page needs the finish card.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter_batch/chapter_batch_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter_page/chapter_page_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/controller/reader_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/reader_screen.dart';
import 'package:tsumiru/src/features/tracking/data/tracker_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/widgets/server_image.dart';

const _png1x1 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=';

class _FakeMangaWithId extends MangaWithId {
  _FakeMangaWithId(this.manga);
  final MangaDto? manga;
  @override
  Future<MangaDto?> build({required int mangaId}) async => manga;
}

GraphQLClient _dummyClient() =>
    GraphQLClient(link: HttpLink('http://localhost:0'), cache: GraphQLCache());

class _FakeTrackerRepository extends TrackerRepository {
  _FakeTrackerRepository() : super(_dummyClient());
  @override
  Future<void> trackProgress(int mangaId) async {}
}

class _QuietRepo extends Fake implements MangaBookRepository {
  @override
  Future<void> putChapter({
    required int chapterId,
    required ChapterChange patch,
  }) async {}
}

/// 1x1 page images, small enough that the card paints without scrolling.
List<String> _localPages(int count, String tag) {
  final dir = Directory.systemTemp.createTempSync('tsumiru-end-card-$tag-');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  final bytes = base64Decode(_png1x1);
  return [
    for (var i = 0; i < count; i++)
      (File('${dir.path}/$i.png')..writeAsBytesSync(bytes)).uri.toString(),
  ];
}

MangaDto _webtoonManga(ReaderMode mode) => Fragment$MangaDto(
  id: 1,
  title: 'Test Webtoon',
  bookmarkCount: 0,
  chapters: Fragment$MangaDto$chapters(totalCount: 1),
  downloadCount: 0,
  genre: const [],
  inLibrary: true,
  inLibraryAt: '0',
  initialized: true,
  meta: [
    Fragment$MangaDto$meta(key: MangaMetaKeys.readerMode.key, value: mode.name),
  ],
  sourceId: '1',
  status: Enum$MangaStatus.ONGOING,
  categories: Fragment$MangaDto$categories(nodes: const []),
  trackRecords: Fragment$MangaDto$trackRecords(totalCount: 0, nodes: const []),
  unreadCount: 1,
  updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
  url: '/manga/1',
);

ChapterDto _chapter({
  required int id,
  required int sourceOrder,
  int pageCount = 1,
}) => Fragment$ChapterDto(
  chapterNumber: sourceOrder.toDouble(),
  fetchedAt: '0',
  id: id,
  isBookmarked: false,
  isDownloaded: false,
  isRead: false,
  lastPageRead: 0,
  lastReadAt: '0',
  mangaId: 1,
  name: 'Chapter $id',
  pageCount: pageCount,
  sourceOrder: sourceOrder,
  uploadDate: '0',
  url: '/chapter/$id',
  meta: const [],
);

ChapterPagesDto _pages(int id, int count) => ChapterPagesDto(
  chapter: ChapterPagesChapterDto(id: id, pageCount: count),
  pages: _localPages(count, 'c$id'),
);

/// Pumps the reader open on a single-page chapter, with [nextChapter] ahead.
Future<void> _pumpReaderOnLastChapter(
  WidgetTester tester, {
  ChapterDto? nextChapter,
  bool chapterListLoaded = true,
  ReaderMode mode = ReaderMode.webtoon,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(const {});
  final prefs = await SharedPreferences.getInstance();

  final ch2 = _chapter(id: 2, sourceOrder: 2);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        mangaBookRepositoryProvider.overrideWithValue(_QuietRepo()),
        mangaWithIdProvider(
          mangaId: 1,
        ).overrideWith(() => _FakeMangaWithId(_webtoonManga(mode))),
        chapterProvider(chapterId: 2).overrideWith((ref) => ch2),
        chapterProvider(
          chapterId: 3,
        ).overrideWith((ref) => _chapter(id: 3, sourceOrder: 3)),
        chapterPagesProvider(chapterId: 2).overrideWith((ref) => _pages(2, 1)),
        chapterPagesProvider(chapterId: 3).overrideWith((ref) => _pages(3, 1)),
        getNextAndPreviousChaptersProvider(
          mangaId: 1,
          chapterId: 2,
          readerScanlatorGroup: '',
        ).overrideWithValue(
          chapterListLoaded ? (first: nextChapter, second: null) : null,
        ),
        trackerRepositoryProvider.overrideWithValue(_FakeTrackerRepository()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ReaderScreen(mangaId: 1, chapterId: 2),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the last page is followed by the finish card and the note', (
    tester,
  ) async {
    await _pumpReaderOnLastChapter(tester);

    final card = find.text('Finished');
    expect(
      card,
      findsOneWidget,
      reason:
          'the strip ends with no finish card, so the last page cannot '
          'scroll clear of the navigation bar and the bottom menu',
    );
    expect(find.text('No more chapters ahead'), findsOneWidget);

    final pageBottom = tester.getBottomLeft(find.byType(ServerImage).first).dy;
    expect(
      tester.getTopLeft(card).dy,
      greaterThan(pageBottom),
      reason: 'the finish card must sit after the last page, not over it',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a chapter ahead still gets the card, without the note', (
    tester,
  ) async {
    await _pumpReaderOnLastChapter(
      tester,
      nextChapter: _chapter(id: 3, sourceOrder: 3),
    );

    expect(find.text('Finished'), findsOneWidget);
    expect(
      find.text('No more chapters ahead'),
      findsNothing,
      reason: 'the end-of-manga note must not show while a chapter is ahead',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unloaded chapter list gets the card, without the note', (
    tester,
  ) async {
    await _pumpReaderOnLastChapter(tester, chapterListLoaded: false);

    expect(find.text('Finished'), findsOneWidget);
    expect(
      find.text('No more chapters ahead'),
      findsNothing,
      reason:
          'a null pair means the list has not loaded, not that the strip '
          'is over',
    );
    expect(tester.takeException(), isNull);
  });

  for (final mode in [
    ReaderMode.continuousHorizontalLTR,
    ReaderMode.continuousHorizontalRTL,
  ]) {
    testWidgets('$mode: the card trails the last page in reading order', (
      tester,
    ) async {
      await _pumpReaderOnLastChapter(tester, mode: mode);

      final reverse = mode == ReaderMode.continuousHorizontalRTL;
      // Content moves negative-x for LTR and positive-x for RTL.
      await tester.timedDrag(
        find.byType(Scrollable).first,
        Offset(reverse ? 1600 : -1600, 0),
        const Duration(milliseconds: 200),
      );
      await tester.pumpAndSettle();

      final card = find.text('Finished');
      expect(card, findsOneWidget);
      expect(find.text('No more chapters ahead'), findsOneWidget);

      final page = find.byType(ServerImage).first;
      if (reverse) {
        expect(
          tester.getTopRight(card).dx,
          lessThan(tester.getTopLeft(page).dx),
          reason: 'RTL: the card belongs past the page, i.e. to its left',
        );
      } else {
        expect(
          tester.getTopLeft(card).dx,
          greaterThan(tester.getTopRight(page).dx),
          reason: 'LTR: the card belongs past the page, i.e. to its right',
        );
      }
      expect(tester.takeException(), isNull);
    });
  }
}
