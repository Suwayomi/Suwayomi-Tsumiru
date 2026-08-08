// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

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
import 'package:tsumiru/src/features/manga_book/presentation/reader/controller/auto_scroll_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/controller/reader_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/reader_screen.dart';
import 'package:tsumiru/src/features/tracking/data/tracker_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

const _png1x1 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=';

class _FakeMangaWithId extends MangaWithId {
  _FakeMangaWithId(this.manga);
  final MangaDto? manga;
  @override
  Future<MangaDto?> build({required int mangaId}) async => manga;
}

GraphQLClient _dummyClient() => GraphQLClient(
      link: HttpLink('http://localhost:0'),
      cache: GraphQLCache(),
    );

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

List<String> _localPages(int count) {
  final dir = Directory.systemTemp.createTempSync('tsumiru-autoscroll-');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  final bytes = base64Decode(_png1x1);
  return [
    for (var i = 0; i < count; i++)
      (File('${dir.path}/$i.png')..writeAsBytesSync(bytes)).uri.toString(),
  ];
}

MangaDto _webtoonManga() => Fragment$MangaDto(
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
        Fragment$MangaDto$meta(
          key: MangaMetaKeys.readerMode.key,
          value: ReaderMode.webtoon.name,
        ),
      ],
      sourceId: '1',
      status: Enum$MangaStatus.ONGOING,
      categories: Fragment$MangaDto$categories(nodes: const []),
      trackRecords:
          Fragment$MangaDto$trackRecords(totalCount: 0, nodes: const []),
      unreadCount: 1,
      updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
      url: '/manga/1',
    );

ChapterDto _chapter() => Fragment$ChapterDto(
      chapterNumber: 1,
      fetchedAt: '0',
      id: 1,
      isBookmarked: false,
      isDownloaded: false,
      isRead: false,
      lastPageRead: 0,
      lastReadAt: '0',
      mangaId: 1,
      name: 'Chapter 1',
      pageCount: 12,
      sourceOrder: 1,
      uploadDate: '0',
      url: '/chapter/1',
      meta: const [],
    );

Future<ProviderContainer> _pumpReader(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  // Chrome visible on purpose. The step-based auto-scroll timer only runs while
  // chrome is hidden, and it stops at the last loaded page — with a 12-page
  // fixture that fires immediately and ends auto-scroll for a reason that has
  // nothing to do with the drag this test is about.
  SharedPreferences.setMockInitialValues(const {'flutter.readerOverlay': true});
  final prefs = await SharedPreferences.getInstance();
  final chapter = _chapter();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        mangaBookRepositoryProvider.overrideWithValue(_QuietRepo()),
        mangaWithIdProvider(mangaId: 1)
            .overrideWith(() => _FakeMangaWithId(_webtoonManga())),
        chapterProvider(chapterId: 1).overrideWith((ref) => chapter),
        chapterPagesProvider(chapterId: 1).overrideWith(
          (ref) => ChapterPagesDto(
            chapter: ChapterPagesChapterDto(id: 1, pageCount: 12),
            pages: _localPages(12),
          ),
        ),
        getNextAndPreviousChaptersProvider(mangaId: 1, chapterId: 1)
            .overrideWithValue((first: null, second: null)),
        trackerRepositoryProvider.overrideWithValue(_FakeTrackerRepository()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ReaderScreen(mangaId: 1, chapterId: 1),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

void main() {
  testWidgets('a drag leaves auto-scroll armed', (tester) async {
    final container = await _pumpReader(tester);

    container.read(autoScrollActiveProvider.notifier).start();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(autoScrollActiveProvider), isTrue);

    await tester.timedDrag(
      find.byType(Scrollable).first,
      const Offset(0, -200),
      const Duration(milliseconds: 120),
    );
    await tester.pumpAndSettle();

    expect(
      container.read(autoScrollActiveProvider),
      isTrue,
      reason: 'a drag hands over the strip; only the toggle ends auto-scroll',
    );
  });

  testWidgets('the reader can still move the strip while auto-scroll runs',
      (tester) async {
    final container = await _pumpReader(tester);

    container.read(autoScrollActiveProvider.notifier).start();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final position = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    final before = position.position.pixels;

    await tester.timedDrag(
      find.byType(Scrollable).first,
      const Offset(0, -240),
      const Duration(milliseconds: 120),
    );
    await tester.pumpAndSettle();

    expect(
      position.position.pixels - before,
      greaterThan(200),
      reason: 'the finger wins: the engine must not fight the drag',
    );
  });
}
