// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// continuousHorizontalLTR/RTL used to be aliases of the paged pager; they now
// route to MultiChapterContinuousReaderMode with scrollDirection:
// Axis.horizontal, reusing the same next/previous-chapter boundary triggers
// as the vertical/webtoon continuous mode (see
// infinity_scrollback_regression_test.dart, which this file mirrors on the
// horizontal axis). This locks down that the axis generalisation actually
// works end-to-end — not just that it compiles — for the direction-gated
// edge-drag trigger that loads a neighbour chapter.

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

List<String> _localPages(int count, String tag) {
  final dir =
      Directory.systemTemp.createTempSync('tsumiru-scrollback-horiz-$tag-');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  final bytes = base64Decode(_png1x1);
  return [
    for (var i = 0; i < count; i++)
      (File('${dir.path}/$i.png')..writeAsBytesSync(bytes)).uri.toString(),
  ];
}

MangaDto _horizontalContinuousManga(ReaderMode mode) => Fragment$MangaDto(
      id: 1,
      title: 'Test Horizontal Continuous',
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
          value: mode.name,
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

/// Pumps the reader open on chapter 2 page 0 (chapter 1 is its previous), in
/// [mode] (continuousHorizontalLTR/RTL).
Future<void> _pumpReaderOnChapter2(
  WidgetTester tester, {
  required ReaderMode mode,
  required FutureOr<ChapterPagesDto?> Function() prevPages,
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
        mangaWithIdProvider(mangaId: 1).overrideWith(
            () => _FakeMangaWithId(_horizontalContinuousManga(mode))),
        chapterProvider(chapterId: 1).overrideWith((ref) => ch1),
        chapterProvider(chapterId: 2).overrideWith((ref) => ch2),
        chapterPagesProvider(chapterId: 1).overrideWith((ref) => prevPages()),
        chapterPagesProvider(chapterId: 2).overrideWith((ref) => _pages(2, 3)),
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

/// A drag gesture toward the start of the horizontal strip: content moves
/// right (mirrors _dragUp's "content moves down" in the vertical regression
/// test). For LTR this pulls toward page 0 / the previous chapter; the sign
/// only matters in that both directions of the axis are exercised across the
/// two tests below (LTR pulls positive, RTL pulls negative).
Future<void> _dragTowardPreviousChapter(
  WidgetTester tester, {
  required bool reverse,
}) async {
  await tester.timedDrag(
    find.byType(Scrollable).first,
    Offset(reverse ? -300 : 300, 0),
    const Duration(milliseconds: 120),
  );
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    MultiChapterContinuousReaderMode.edgeAttemptCooldown = Duration.zero;
  });
  tearDown(() {
    MultiChapterContinuousReaderMode.edgeAttemptCooldown =
        const Duration(seconds: 4);
  });

  for (final mode in [
    ReaderMode.continuousHorizontalLTR,
    ReaderMode.continuousHorizontalRTL,
  ]) {
    testWidgets(
        '$mode: mounts as a real horizontal continuous strip (never the '
        'paged pager)', (tester) async {
      await _pumpReaderOnChapter2(
        tester,
        mode: mode,
        prevPages: () async => _pages(1, 3),
      );

      final widget = tester.widget<MultiChapterContinuousReaderMode>(
        find.byType(MultiChapterContinuousReaderMode),
      );
      expect(widget.scrollDirection, Axis.horizontal);
      expect(widget.reverse, mode == ReaderMode.continuousHorizontalRTL);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '$mode: resume at page 0, a drag at the clamp loads the previous '
        'chapter', (tester) async {
      var prevFetches = 0;
      await _pumpReaderOnChapter2(
        tester,
        mode: mode,
        prevPages: () async {
          prevFetches++;
          // Real delay: an unheld autoDispose fetch would get disposed
          // mid-flight and never complete.
          await Future<void>.delayed(const Duration(milliseconds: 100));
          return _pages(1, 3);
        },
      );

      await _dragTowardPreviousChapter(
        tester,
        reverse: mode == ReaderMode.continuousHorizontalRTL,
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(prevFetches, greaterThanOrEqualTo(1),
          reason: 'edge drag on the horizontal strip never asked for the '
              'previous chapter — the boundary trigger only works on the '
              'vertical axis');
      expect(tester.takeException(), isNull);
    });
  }
}
