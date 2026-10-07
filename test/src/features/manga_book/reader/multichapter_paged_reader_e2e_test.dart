// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
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
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_mode/multichapter_paged_reader_mode.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_mode/paged_reader_viewport.dart';
import 'package:tsumiru/src/features/tracking/data/tracker_repository.dart';
import 'package:tsumiru/src/features/tracking/domain/tracking_settings_providers.dart';
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

GraphQLClient _dummyClient() =>
    GraphQLClient(link: HttpLink('http://localhost:0'), cache: GraphQLCache());

class _FakeTrackerRepository extends TrackerRepository {
  _FakeTrackerRepository() : super(_dummyClient());
  @override
  Future<void> trackProgress(int mangaId) async {}
}

class _FixedToggle extends UpdateProgressAfterReading {
  _FixedToggle(this._value);
  final bool _value;
  @override
  bool? build() => _value;
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

List<String> _localPages(int count, String tag) {
  final dir = Directory.systemTemp.createTempSync('tsumiru-e2e-$tag-');
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
  chapters: Fragment$MangaDto$chapters(totalCount: 2),
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
  trackRecords: Fragment$MangaDto$trackRecords(totalCount: 0, nodes: const []),
  unreadCount: 2,
  updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
  url: '/manga/1',
);

ChapterDto _chapter({
  required int id,
  required int sourceOrder,
  required int pageCount,
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

void main() {
  testWidgets('paged reader loads and crosses into the next chapter in-place', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    final repo = _RecordingRepo();

    final ch1 = _chapter(id: 1, sourceOrder: 1, pageCount: 3);
    final ch2 = _chapter(id: 2, sourceOrder: 2, pageCount: 2);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          mangaBookRepositoryProvider.overrideWithValue(repo),
          mangaWithIdProvider(
            mangaId: 1,
          ).overrideWith(() => _FakeMangaWithId(_manga())),
          chapterProvider(chapterId: 1).overrideWith((ref) => ch1),
          chapterProvider(chapterId: 2).overrideWith((ref) => ch2),
          chapterPagesProvider(
            chapterId: 1,
          ).overrideWith((ref) => _pages(1, 3)),
          chapterPagesProvider(
            chapterId: 2,
          ).overrideWith((ref) => _pages(2, 2)),
          // Chapter 1 has a next (chapter 2); chapter 2 has a previous (1).
          getNextAndPreviousChaptersProvider(
            mangaId: 1,
            chapterId: 1,
            readerScanlatorGroup: '',
          ).overrideWithValue((first: ch2, second: null)),
          getNextAndPreviousChaptersProvider(
            mangaId: 1,
            chapterId: 2,
            readerScanlatorGroup: '',
          ).overrideWithValue((first: null, second: ch1)),
          // Keep the external tracker path inert in the test.
          trackerRepositoryProvider.overrideWithValue(_FakeTrackerRepository()),
          updateProgressAfterReadingProvider.overrideWith(
            () => _FixedToggle(false),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ReaderScreen(mangaId: 1, chapterId: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Opens on chapter 1 (3 pages).
    expect(find.text('1 / 3'), findsOneWidget);

    // Read forward through chapter 1. The host preloads chapter 2 near the edge,
    // commits the window swap on idle, and paging flows straight into it.
    for (var i = 0; i < 6; i++) {
      await tester.timedDrag(
        find.byType(PagedReaderViewport),
        const Offset(-400, 0),
        const Duration(milliseconds: 80),
      );
      await tester.pumpAndSettle();
      // Let the async chapter load + idle-gated commit settle.
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
    }

    expect(tester.takeException(), isNull);

    // We must have crossed into chapter 2 — its page count (2) now drives the
    // seekbar, which never shows "/ 2" while reading the 3-page chapter 1.
    expect(
      find.textContaining('/ 2'),
      findsOneWidget,
      reason: 'reader never crossed into chapter 2',
    );

    // Crossing the boundary forward marks chapter 1 read.
    expect(
      repo.putChapterCalls.any(
        (c) => c.chapterId == 1 && c.patch.isRead == true,
      ),
      isTrue,
      reason: 'chapter 1 was not marked read on the forward crossing',
    );
  });

  Future<_RecordingRepo> pumpSingleChapter(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    final repo = _RecordingRepo();
    final ch1 = _chapter(id: 1, sourceOrder: 1, pageCount: 3);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          mangaBookRepositoryProvider.overrideWithValue(repo),
          mangaWithIdProvider(
            mangaId: 1,
          ).overrideWith(() => _FakeMangaWithId(_manga())),
          chapterProvider(chapterId: 1).overrideWith((ref) => ch1),
          chapterPagesProvider(
            chapterId: 1,
          ).overrideWith((ref) => _pages(1, 3)),
          getNextAndPreviousChaptersProvider(
            mangaId: 1,
            chapterId: 1,
          ).overrideWithValue(null),
          trackerRepositoryProvider.overrideWithValue(_FakeTrackerRepository()),
          updateProgressAfterReadingProvider.overrideWith(
            () => _FixedToggle(false),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ReaderScreen(mangaId: 1, chapterId: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('saves the visible page after the debounce', (tester) async {
    final repo = await pumpSingleChapter(tester);

    // Turn to page 2 (index 1).
    await tester.timedDrag(
      find.byType(PagedReaderViewport),
      const Offset(-400, 0),
      const Duration(milliseconds: 80),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);

    // Let the 2s progress debounce fire.
    await tester.pump(const Duration(seconds: 3));

    expect(
      // Partial read: position is saved, read-state is omitted (never un-reads).
      repo.putChapterCalls.any(
        (c) =>
            c.chapterId == 1 &&
            c.patch.lastPageRead == 1 &&
            c.patch.isRead == null,
      ),
      isTrue,
      reason:
          'debounced progress for page 2 was not saved; ${repo.putChapterCalls}',
    );
  });

  testWidgets('flushes the visible page on exit before the debounce fires', (
    tester,
  ) async {
    final repo = await pumpSingleChapter(tester);

    await tester.timedDrag(
      find.byType(PagedReaderViewport),
      const Offset(-400, 0),
      const Duration(milliseconds: 80),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);

    // Leave the reader well within the 2s debounce window.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      repo.putChapterCalls.any(
        (c) => c.chapterId == 1 && c.patch.lastPageRead == 1,
      ),
      isTrue,
      reason: 'progress was not flushed on exit; ${repo.putChapterCalls}',
    );
  });

  // The reader keeps going across a network change: an endpoint switch (LAN
  // <-> external) or the server coming back rebuilds every reader provider.
  group('chapter loading across an endpoint switch', () {
    Future<Element> pumpReader(
      WidgetTester tester, {
      required bool nextKnownBeforeSwitch,
    }) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues(const {});
      final prefs = await SharedPreferences.getInstance();
      final ch1 = _chapter(id: 1, sourceOrder: 1, pageCount: 3);
      final ch2 = _chapter(id: 2, sourceOrder: 2, pageCount: 2);
      final pages1 = _pages(1, 3);
      final pages2 = _pages(2, 2);

      // Each switch reloads through a dependency change, slowly enough to
      // show a loading state.
      Future<T> reloadable<T>(Ref ref, T value) async {
        if (ref.watch(_endpointProvider) == 0) return value;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return value;
      }

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            mangaBookRepositoryProvider.overrideWithValue(_RecordingRepo()),
            mangaWithIdProvider(
              mangaId: 1,
            ).overrideWith(() => _FakeMangaWithId(_manga())),
            chapterProvider(
              chapterId: 1,
            ).overrideWith((ref) => reloadable(ref, ch1)),
            chapterProvider(
              chapterId: 2,
            ).overrideWith((ref) => reloadable(ref, ch2)),
            chapterPagesProvider(
              chapterId: 1,
            ).overrideWith((ref) => reloadable(ref, pages1)),
            chapterPagesProvider(
              chapterId: 2,
            ).overrideWith((ref) => reloadable(ref, pages2)),
            // Before the switch the list may come from the device and lack
            // chapter 2 (not downloaded yet); after it, the server's list has it.
            getNextAndPreviousChaptersProvider(
              mangaId: 1,
              chapterId: 1,
              readerScanlatorGroup: '',
            ).overrideWith(
              (ref) => ref.watch(_endpointProvider) > 0 || nextKnownBeforeSwitch
                  ? (first: ch2, second: null)
                  : (first: null, second: null),
            ),
            getNextAndPreviousChaptersProvider(
              mangaId: 1,
              chapterId: 2,
              readerScanlatorGroup: '',
            ).overrideWith((ref) {
              ref.watch(_endpointProvider);
              return (first: null, second: ch1);
            }),
            trackerRepositoryProvider.overrideWithValue(
              _FakeTrackerRepository(),
            ),
            updateProgressAfterReadingProvider.overrideWith(
              () => _FixedToggle(false),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ReaderScreen(mangaId: 1, chapterId: 1),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 / 3'), findsOneWidget);
      return tester.element(find.byType(MultiChapterPagedReaderMode));
    }

    Future<void> pageForward(WidgetTester tester, int times) async {
      for (var i = 0; i < times; i++) {
        await tester.timedDrag(
          find.byType(PagedReaderViewport),
          const Offset(-400, 0),
          const Duration(milliseconds: 80),
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpAndSettle();
      }
    }

    Future<void> switchEndpoint(WidgetTester tester) async {
      ProviderScope.containerOf(
        tester.element(find.byType(ReaderScreen)),
      ).read(_endpointProvider.notifier).switchEndpoint();
      await tester.pump();
      await tester.pumpAndSettle();
    }

    testWidgets('loads the next chapter after a switch and stays in it '
        'through another one', (tester) async {
      final engine = await pumpReader(tester, nextKnownBeforeSwitch: true);

      await pageForward(tester, 1);
      expect(find.text('2 / 3'), findsOneWidget);

      await switchEndpoint(tester);
      expect(find.text('2 / 3'), findsOneWidget);

      await pageForward(tester, 5);
      expect(
        find.textContaining('/ 2'),
        findsOneWidget,
        reason: 'reader never crossed into chapter 2 after the switch',
      );

      // The reported jump: a switch while reading a chapter loaded in-place
      // sent the reader back to the chapter it was opened on.
      await switchEndpoint(tester);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('/ 2'), findsOneWidget);
      expect(
        tester.element(find.byType(MultiChapterPagedReaderMode)),
        same(engine),
        reason: 'the reader was remounted',
      );
    });

    testWidgets('a next chapter missing before the switch loads after it', (
      tester,
    ) async {
      final engine = await pumpReader(tester, nextKnownBeforeSwitch: false);

      await pageForward(tester, 4);
      expect(find.text('3 / 3'), findsOneWidget);

      await switchEndpoint(tester);
      // Past the end card, through the transition card, into chapter 2.
      await pageForward(tester, 5);

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('/ 2'),
        findsOneWidget,
        reason: 'the next chapter never loaded once the list had it',
      );
      expect(
        tester.element(find.byType(MultiChapterPagedReaderMode)),
        same(engine),
        reason: 'the reader was remounted',
      );
    });
  });
}

/// Stands in for the active server endpoint every reader provider depends on.
class _Endpoint extends Notifier<int> {
  @override
  int build() => 0;

  void switchEndpoint() => state++;
}

final _endpointProvider = NotifierProvider<_Endpoint, int>(_Endpoint.new);
