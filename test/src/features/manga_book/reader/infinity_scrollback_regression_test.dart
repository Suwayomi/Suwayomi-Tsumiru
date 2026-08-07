// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Regression tests for the v0.9.0 infinity-scroll boundary deadlocks:
// 1. Resume on page 0 → an upward drag is fully clamped, the position
//    listener never ticks, and the previous chapter could never load.
// 2. One failed/null page fetch latched "reached start/end" for the session.
// 3. A cold open read the next/prev pair once while the chapter list was
//    still loading, pinning both neighbours to null for the session.

import 'dart:async';
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
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_mode/infinity_continuous/multichapter_continuous_reader_mode.dart';
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

/// Whether the cold-open pair test has "resolved" its chapter list yet.
class _PairReady extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool value) => state = value;
}

final _pairReadyProvider = NotifierProvider<_PairReady, bool>(_PairReady.new);

List<String> _localPages(int count, String tag) {
  final dir = Directory.systemTemp.createTempSync('tsumiru-scrollback-$tag-');
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
      chapters: Fragment$MangaDto$chapters(totalCount: 2),
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
      unreadCount: 2,
      updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
      url: '/manga/1',
    );

ChapterDto _chapter({required int id, required int sourceOrder}) =>
    Fragment$ChapterDto(
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
      pageCount: 3,
      sourceOrder: sourceOrder,
      uploadDate: '0',
      url: '/chapter/$id',
      meta: const [],
    );

ChapterPagesDto _pages(int id, int count) => ChapterPagesDto(
      chapter: ChapterPagesChapterDto(id: id, pageCount: count),
      pages: _localPages(count, 'c$id'),
    );

/// Pumps the reader open on chapter 2 page 0 (chapter 1 is its previous).
/// [prevPages] controls what chapterPagesProvider(1) produces per fetch.
/// [coldOpenPair] gates ch2's next/prev pair behind [_pairReadyProvider].
Future<void> _pumpReaderOnChapter2(
  WidgetTester tester, {
  required FutureOr<ChapterPagesDto?> Function() prevPages,
  bool coldOpenPair = false,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(const {});
  final prefs = await SharedPreferences.getInstance();

  final ch1 = _chapter(id: 1, sourceOrder: 1);
  final ch2 = _chapter(id: 2, sourceOrder: 2);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        mangaBookRepositoryProvider.overrideWithValue(_QuietRepo()),
        mangaWithIdProvider(mangaId: 1)
            .overrideWith(() => _FakeMangaWithId(_webtoonManga())),
        chapterProvider(chapterId: 1).overrideWith((ref) => ch1),
        chapterProvider(chapterId: 2).overrideWith((ref) => ch2),
        chapterPagesProvider(chapterId: 1).overrideWith((ref) => prevPages()),
        chapterPagesProvider(chapterId: 2).overrideWith((ref) => _pages(2, 3)),
        if (coldOpenPair)
          getNextAndPreviousChaptersProvider(mangaId: 1, chapterId: 2)
              .overrideWith((ref) => ref.watch(_pairReadyProvider)
                  ? (first: null, second: ch1)
                  : null)
        else
          getNextAndPreviousChaptersProvider(mangaId: 1, chapterId: 2)
              .overrideWithValue((first: null, second: ch1)),
        getNextAndPreviousChaptersProvider(mangaId: 1, chapterId: 1)
            .overrideWithValue((first: ch2, second: null)),
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

/// An upward scroll gesture (drag the content downward) on the reader body.
Future<void> _dragUp(WidgetTester tester) async {
  await tester.timedDrag(
    find.byType(Scrollable).first,
    const Offset(0, 300),
    const Duration(milliseconds: 120),
  );
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    // Wall-clock time doesn't advance in widget tests; drop the gesture
    // cooldown so successive drags count as separate attempts.
    MultiChapterContinuousReaderMode.edgeAttemptCooldown = Duration.zero;
  });
  tearDown(() {
    MultiChapterContinuousReaderMode.edgeAttemptCooldown =
        const Duration(seconds: 4);
  });

  testWidgets(
      'resume at page 0: an upward drag at the clamp loads the previous chapter',
      (tester) async {
    var prevFetches = 0;
    await _pumpReaderOnChapter2(
      tester,
      // Async with a real delay: an unheld autoDispose fetch gets disposed
      // mid-flight and never completes (the "loading… that never loads").
      prevPages: () async {
        prevFetches++;
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return _pages(1, 3);
      },
    );

    // No downward movement first — the deadlock precondition.
    await _dragUp(tester);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(prevFetches, greaterThanOrEqualTo(1),
        reason: 'blocked upward drag at page 0 never asked for the previous '
            'chapter (the resume deadlock)');

    // A second pull must be a no-op: the chapter LOADED, so the engine's
    // already-loaded guard stops a refetch. If the fetch had been disposed
    // mid-flight (never completing), this drag would fetch again.
    await _dragUp(tester);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(prevFetches, 1,
        reason: 'previous chapter never finished loading; the fetch was '
            'disposed mid-flight and the gesture refetched');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed previous-chapter fetch does not latch for the session',
      (tester) async {
    var prevFetches = 0;
    await _pumpReaderOnChapter2(
      tester,
      prevPages: () {
        prevFetches++;
        // First fetch fails (returns nothing); later fetches succeed.
        if (prevFetches == 1) return null;
        return _pages(1, 3);
      },
    );

    // The gesture must retry past the failed fetch instead of latching a
    // "reached start" state (pre-fix, the count froze at 1 forever).
    await _dragUp(tester);
    await _dragUp(tester);
    expect(prevFetches, greaterThanOrEqualTo(2),
        reason: 'failed fetch latched the boundary; no retry happened');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'cold open: neighbours resolving after mount still enable the boundary',
      (tester) async {
    var prevFetches = 0;

    await _pumpReaderOnChapter2(
      tester,
      prevPages: () {
        prevFetches++;
        return _pages(1, 3);
      },
      // Pair is null (chapter list "still loading") until the switch flips.
      coldOpenPair: true,
    );

    // While unresolved, an upward drag can't load anything — and must not latch.
    await _dragUp(tester);
    expect(prevFetches, 0);

    // The chapter list "finishes loading".
    final container = ProviderScope.containerOf(
        tester.element(find.byType(ReaderScreen)));
    container.read(_pairReadyProvider.notifier).set(true);
    await tester.pumpAndSettle();

    // The same gesture now works — the reader watched the pair instead of
    // reading it once at mount.
    await _dragUp(tester);
    expect(prevFetches, greaterThanOrEqualTo(1),
        reason: 'neighbours resolved after mount were never picked up '
            '(the cold-open race)');
    expect(tester.takeException(), isNull);
  });
}
