// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
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
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_mode/paged_reader_viewport.dart';
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

class _RecordingRepo extends Fake implements MangaBookRepository {
  final putChapterCalls = <({int chapterId, ChapterChange patch})>[];

  @override
  Future<void> putChapter({
    required int chapterId,
    required ChapterChange patch,
  }) async {
    putChapterCalls.add((chapterId: chapterId, patch: patch));
  }
}

List<String> _localPages(int count) {
  final dir = Directory.systemTemp.createTempSync('tsumiru-reader-screen-');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  final bytes = base64Decode(_png1x1);
  return [
    for (var i = 0; i < count; i++)
      (File('${dir.path}/$i.png')..writeAsBytesSync(bytes)).uri.toString(),
  ];
}

MangaDto _manga() => Fragment$MangaDto(
      id: 1,
      title: 'Test Manga',
      bookmarkCount: 0,
      chapters: Fragment$MangaDto$chapters(totalCount: 0),
      downloadCount: 0,
      genre: const [],
      inLibrary: true,
      inLibraryAt: '0',
      initialized: true,
      meta: [
        Fragment$MangaDto$meta(
          key: MangaMetaKeys.readerMode.key,
          value: ReaderMode.singleHorizontalLTR.name,
        ),
      ],
      sourceId: '1',
      status: Enum$MangaStatus.ONGOING,
      categories: Fragment$MangaDto$categories(nodes: const []),
      trackRecords:
          Fragment$MangaDto$trackRecords(totalCount: 0, nodes: const []),
      unreadCount: 0,
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
      pageCount: 3,
      sourceOrder: 1,
      uploadDate: '0',
      url: '/chapter/1',
      meta: const [],
    );

ChapterDto _partReadChapter() => Fragment$ChapterDto(
      chapterNumber: 1,
      fetchedAt: '0',
      id: 1,
      isBookmarked: false,
      isDownloaded: false,
      isRead: false,
      lastPageRead: 1,
      lastReadAt: '0',
      mangaId: 1,
      name: 'Chapter 1',
      pageCount: 3,
      sourceOrder: 1,
      uploadDate: '0',
      url: '/chapter/1',
      meta: const [],
    );

ChapterPagesDto _chapterPages() => ChapterPagesDto(
      chapter: ChapterPagesChapterDto(id: 1, pageCount: 3),
      pages: _localPages(3),
    );

void main() {
  testWidgets('flushes debounced progress when the reader unmounts without a pop',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    final repo = _RecordingRepo();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          mangaBookRepositoryProvider.overrideWithValue(repo),
          mangaWithIdProvider(mangaId: 1)
              .overrideWith(() => _FakeMangaWithId(_manga())),
          chapterProvider(chapterId: 1).overrideWith((ref) => _chapter()),
          chapterPagesProvider(chapterId: 1)
              .overrideWith((ref) => _chapterPages()),
          getNextAndPreviousChaptersProvider(mangaId: 1, chapterId: 1)
              .overrideWithValue(null),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ReaderScreen(mangaId: 1, chapterId: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.timedDrag(
      find.byType(PagedReaderViewport),
      const Offset(-320, 0),
      const Duration(milliseconds: 80),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 / 3'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));

    expect(tester.takeException(), isNull);
    // Chapter-skip transitions dispose the reader via pushReplacement, without a
    // PopScope pop — the pending page must be flushed here, not dropped.
    expect(repo.putChapterCalls, hasLength(1));
    expect(repo.putChapterCalls.single.chapterId, 1);
    expect(repo.putChapterCalls.single.patch.lastPageRead, 1);
    expect(repo.putChapterCalls.single.patch.isRead, isFalse);
  });

  testWidgets('flushes debounced progress when the reader route pops',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    final repo = _RecordingRepo();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          mangaBookRepositoryProvider.overrideWithValue(repo),
          mangaWithIdProvider(mangaId: 1)
              .overrideWith(() => _FakeMangaWithId(_manga())),
          chapterProvider(chapterId: 1).overrideWith((ref) => _chapter()),
          chapterPagesProvider(chapterId: 1)
              .overrideWith((ref) => _chapterPages()),
          getNextAndPreviousChaptersProvider(mangaId: 1, chapterId: 1)
              .overrideWithValue(null),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        const ReaderScreen(mangaId: 1, chapterId: 1),
                  ),
                );
              },
              child: const Text('Open reader'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open reader'));
    await tester.pumpAndSettle();

    await tester.timedDrag(
      find.byType(PagedReaderViewport),
      const Offset(-320, 0),
      const Duration(milliseconds: 80),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 / 3'), findsOneWidget);

    Navigator.of(tester.element(find.byType(ReaderScreen))).pop();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(repo.putChapterCalls, hasLength(1));
    expect(repo.putChapterCalls.single.chapterId, 1);
    expect(repo.putChapterCalls.single.patch.lastPageRead, 1);
    expect(repo.putChapterCalls.single.patch.isRead, isFalse);
  });

  testWidgets('opening at the end does not mark an unread chapter read',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    final repo = _RecordingRepo();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          mangaBookRepositoryProvider.overrideWithValue(repo),
          mangaWithIdProvider(mangaId: 1)
              .overrideWith(() => _FakeMangaWithId(_manga())),
          chapterProvider(chapterId: 1)
              .overrideWith((ref) => _partReadChapter()),
          chapterPagesProvider(chapterId: 1)
              .overrideWith((ref) => _chapterPages()),
          getNextAndPreviousChaptersProvider(mangaId: 1, chapterId: 1)
              .overrideWithValue(null),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ReaderScreen(mangaId: 1, chapterId: 1, openAtEnd: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Paging back into a chapter opens it on its last page. The on-mount emit
    // must not count as reading — otherwise the chapter is marked read and its
    // resume position wiped just by navigating to it.
    expect(find.text('3 / 3'), findsOneWidget);
    expect(repo.putChapterCalls, isEmpty);
  });
}
