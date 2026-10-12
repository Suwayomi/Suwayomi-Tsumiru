// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/chrome/reader_top_bar.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_mode/reader_zoom_view.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_navigation_layout/layouts/l_shaped_layout.dart';
import 'package:tsumiru/src/features/settings/presentation/downloads/data/delete_chapters_settings_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/downloads/data/graphql/__generated__/global_meta.graphql.dart';
import 'package:tsumiru/src/features/tracking/data/tracker_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/motion/reduce_motion.dart';

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

class _NoGlobalMetasRepository extends Fake
    implements DeleteChaptersSettingsRepository {
  @override
  Future<List<Fragment$GlobalMetaDto>?> getGlobalMetas() async => const [];
}

class _FixedReduceMotion extends AppReduceMotion {
  _FixedReduceMotion(this._value);
  final bool _value;
  @override
  bool build() => _value;
}

List<String> _localPages(int count, String tag) {
  final dir = Directory.systemTemp.createTempSync('tsumiru-reduced-$tag-');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  final bytes = base64Decode(_png1x1);
  return [
    for (var i = 0; i < count; i++)
      (File('${dir.path}/$i.png')..writeAsBytesSync(bytes)).uri.toString(),
  ];
}

MangaDto _longStripManga() => Fragment$MangaDto(
  id: 1,
  title: 'Test Long Strip',
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
  trackRecords: Fragment$MangaDto$trackRecords(nodes: const []),
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

ChapterPagesDto _pages(int id) => ChapterPagesDto(
  chapter: ChapterPagesChapterDto(id: id, pageCount: 3),
  pages: _localPages(3, 'c$id'),
);

Future<void> _pumpLongStrip(
  WidgetTester tester, {
  required bool reduceMotion,
  bool animatePageTransitions = true,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({
    'animatePageTransitions': animatePageTransitions,
  });
  final prefs = await SharedPreferences.getInstance();

  final ch1 = _chapter(id: 1, sourceOrder: 1);
  final ch2 = _chapter(id: 2, sourceOrder: 2);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appReduceMotionProvider.overrideWith(
          () => _FixedReduceMotion(reduceMotion),
        ),
        mangaBookRepositoryProvider.overrideWithValue(_QuietRepo()),
        mangaWithIdProvider(
          mangaId: 1,
        ).overrideWith(() => _FakeMangaWithId(_longStripManga())),
        chapterProvider(chapterId: 1).overrideWith((ref) => ch1),
        chapterProvider(chapterId: 2).overrideWith((ref) => ch2),
        chapterPagesProvider(chapterId: 1).overrideWith((ref) => _pages(1)),
        chapterPagesProvider(chapterId: 2).overrideWith((ref) => _pages(2)),
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
        trackerRepositoryProvider.overrideWithValue(_FakeTrackerRepository()),
        deleteChaptersSettingsRepositoryProvider.overrideWithValue(
          _NoGlobalMetasRepository(),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => ReduceMotionScope(child: child!),
        home: const ReaderScreen(mangaId: 1, chapterId: 1),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ScrollPosition _listPosition(WidgetTester tester) => tester
    .stateList<ScrollableState>(find.byType(Scrollable))
    .map((state) => state.position)
    .where((position) => position.axis == Axis.vertical)
    .reduce((a, b) => a.maxScrollExtent >= b.maxScrollExtent ? a : b);

double _topBarOpacity(WidgetTester tester) => tester
    .widget<FadeTransition>(
      find
          .ancestor(
            of: find.byType(ReaderTopBar),
            matching: find.byType(FadeTransition),
          )
          .first,
    )
    .opacity
    .value;

void main() {
  group('long strip tap scroll', () {
    testWidgets('reduced motion jumps the full distance after one pump', (
      tester,
    ) async {
      await _pumpLongStrip(tester, reduceMotion: true);
      final before = _listPosition(tester).pixels;

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      final afterOnePump = _listPosition(tester).pixels;
      await tester.pumpAndSettle();

      expect(afterOnePump, greaterThan(before));
      expect(afterOnePump, _listPosition(tester).pixels);
    });

    testWidgets('with Animate page transitions off it jumps', (tester) async {
      await _pumpLongStrip(
        tester,
        reduceMotion: false,
        animatePageTransitions: false,
      );
      final before = _listPosition(tester).pixels;

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      final afterOnePump = _listPosition(tester).pixels;
      await tester.pumpAndSettle();

      expect(afterOnePump, greaterThan(before));
      expect(afterOnePump, _listPosition(tester).pixels);
    });

    testWidgets('with defaults it still animates', (tester) async {
      await _pumpLongStrip(tester, reduceMotion: false);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      final afterOnePump = _listPosition(tester).pixels;
      await tester.pumpAndSettle();

      expect(afterOnePump, lessThan(_listPosition(tester).pixels));
    });
  });

  for (final reduce in [true, false]) {
    testWidgets(
      'drag inside tap zone scrolls the strip with reduced motion=$reduce',
      (tester) async {
        await _pumpLongStrip(tester, reduceMotion: reduce);
        expect(find.byType(LShapedLayout), findsOneWidget);
        final before = _listPosition(tester).pixels;

        await tester.dragFrom(const Offset(50, 800), const Offset(0, -300));
        await tester.pumpAndSettle();

        expect(_listPosition(tester).pixels, closeTo(before + 300, 60));
      },
    );
  }

  testWidgets('reduced motion shows the reader menu at once', (tester) async {
    await _pumpLongStrip(tester, reduceMotion: true);
    expect(_topBarOpacity(tester), 0.0);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(_topBarOpacity(tester), 1.0);
  });

  testWidgets('with defaults the reader menu still fades in', (tester) async {
    await _pumpLongStrip(tester, reduceMotion: false);
    expect(_topBarOpacity(tester), 0.0);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(_topBarOpacity(tester), lessThan(1.0));
  });

  for (final reduce in [true, false]) {
    testWidgets('long strip double tap zoom with reduced motion=$reduce', (
      tester,
    ) async {
      final scales = <double>[];
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
            child: child!,
          ),
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: ReaderZoomView(
                controller: scrollController,
                scrollAxis: Axis.vertical,
                maxScale: 3.0,
                minScale: 1.0,
                pinchEnabled: true,
                doubleTapToZoom: true,
                onScaleChanged: scales.add,
                child: ListView(
                  controller: scrollController,
                  children: const [SizedBox(height: 1200)],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final center = tester.getCenter(find.byType(ReaderZoomView));
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(center);
      await tester.pump();

      if (reduce) {
        expect(scales.last, closeTo(3.0, 0.01));
      } else {
        expect(scales.last, lessThan(3.0));
      }
      await tester.pump(const Duration(milliseconds: 500));
    });
  }
}
