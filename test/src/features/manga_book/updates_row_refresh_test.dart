// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/updates/updates_row_patch.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/controller/reader_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/updates/updates_screen.dart';
import 'package:tsumiru/src/features/manga_book/presentation/updates/widgets/chapter_manga_list_tile.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

const _kMangaId = 7;

final _watchedAfterAsyncGap = Provider<int>((ref) => 1);

Fragment$MangaBaseDto _manga({int id = _kMangaId}) => Fragment$MangaBaseDto(
  id: id,
  genre: const [],
  inLibrary: true,
  inLibraryAt: '0',
  initialized: true,
  meta: const [],
  sourceId: '1',
  status: Enum$MangaStatus.ONGOING,
  thumbnailUrl: '/thumb/$id',
  title: 'Series $id',
  unreadCount: 3,
  updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
  url: '/manga/$id',
);

ChapterWithMangaDto _row({
  required int id,
  int mangaId = _kMangaId,
  bool isRead = false,
  bool isDownloaded = false,
  int lastPageRead = 0,
}) => Fragment$ChapterWithMangaDto(
  id: id,
  chapterNumber: id.toDouble(),
  fetchedAt: '0',
  isBookmarked: false,
  isDownloaded: isDownloaded,
  isRead: isRead,
  lastPageRead: lastPageRead,
  lastReadAt: '0',
  mangaId: mangaId,
  name: 'Chapter $id',
  pageCount: 10,
  sourceOrder: id,
  uploadDate: '0',
  url: '/c/$id',
  meta: const [],
  manga: _manga(id: mangaId),
);

ChapterDto _fresh({
  required int id,
  int mangaId = _kMangaId,
  bool isRead = false,
  bool isBookmarked = false,
  bool isDownloaded = false,
  int lastPageRead = 0,
}) => Fragment$ChapterDto(
  id: id,
  chapterNumber: id.toDouble(),
  fetchedAt: '0',
  isBookmarked: isBookmarked,
  isDownloaded: isDownloaded,
  isRead: isRead,
  lastPageRead: lastPageRead,
  lastReadAt: '0',
  mangaId: mangaId,
  name: 'Chapter $id',
  pageCount: 10,
  sourceOrder: id,
  uploadDate: '0',
  url: '/c/$id',
  meta: const [],
);

void main() {
  group('patchRowsForManga', () {
    test('greys out every chapter of the series that was read', () {
      final rows = [_row(id: 1), _row(id: 2), _row(id: 3)];

      final patched = patchRowsForManga(
        rows: rows,
        mangaId: _kMangaId,
        chapters: [
          _fresh(id: 1, isRead: true),
          _fresh(id: 2, isRead: true),
          _fresh(id: 3),
        ],
      );

      expect(patched.map((e) => e.isRead), [true, true, false]);
    });

    test('leaves other series alone', () {
      final rows = [_row(id: 1), _row(id: 9, mangaId: 99)];

      final patched = patchRowsForManga(
        rows: rows,
        mangaId: _kMangaId,
        chapters: [_fresh(id: 1, isRead: true), _fresh(id: 9, isRead: true)],
      );

      expect(patched[1].isRead, isFalse);
    });

    test('keeps rows the refreshed list no longer covers', () {
      final rows = [_row(id: 1, isRead: true, lastPageRead: 5)];

      final patched = patchRowsForManga(
        rows: rows,
        mangaId: _kMangaId,
        chapters: [_fresh(id: 2)],
      );

      expect(patched.single.isRead, isTrue);
      expect(patched.single.lastPageRead, 5);
    });

    test('carries download state and progress across', () {
      final patched = patchRowsForManga(
        rows: [_row(id: 1)],
        mangaId: _kMangaId,
        chapters: [_fresh(id: 1, isDownloaded: true, lastPageRead: 12)],
      );

      expect(patched.single.isDownloaded, isTrue);
      expect(patched.single.lastPageRead, 12);
    });

    test('a lagging refetch cannot un-read a row', () {
      final patched = patchRowsForManga(
        rows: [_row(id: 1, isRead: true)],
        mangaId: _kMangaId,
        chapters: [_fresh(id: 1)],
      );

      expect(patched.single.isRead, isTrue);
    });

    test('a series the fetch could not reach at all is left alone', () {
      final rows = [_row(id: 1, isRead: true), _row(id: 2)];

      final patched = patchRowsForManga(
        rows: rows,
        mangaId: _kMangaId,
        chapters: const [],
      );

      expect(patched.map((e) => e.isRead), [true, false]);
    });

    test('a bookmark set while reading shows on the row', () {
      final patched = patchRowsForManga(
        rows: [_row(id: 1)],
        mangaId: _kMangaId,
        chapters: [_fresh(id: 1, isBookmarked: true)],
      );

      expect(patched.single.isBookmarked, isTrue);
    });

    test('a chapter from another series cannot patch this one', () {
      final patched = patchRowsForManga(
        rows: [_row(id: 1)],
        mangaId: _kMangaId,
        chapters: [_fresh(id: 1, mangaId: 99, isRead: true)],
      );

      expect(patched.single.isRead, isFalse);
    });
  });

  group('fetchChaptersInBatches', () {
    test('never has more than the batch size in flight', () async {
      var inFlight = 0, peak = 0;

      final chapters = await fetchChaptersInBatches(
        ids: List.generate(20, (i) => i + 1),
        batchSize: 4,
        fetch: (id) async {
          peak = max(peak, ++inFlight);
          await Future<void>.delayed(Duration.zero);
          inFlight--;
          return _fresh(id: id);
        },
      );

      expect(peak, lessThanOrEqualTo(4));
      expect(chapters.length, 20);
    });

    test('one failing chapter does not sink the rest', () async {
      final chapters = await fetchChaptersInBatches(
        ids: [1, 2, 3],
        batchSize: 4,
        fetch: (id) async {
          if (id == 2) throw Exception('not in the on-device catalog');
          return _fresh(id: id);
        },
      );

      expect(chapters.map((e) => e.id), [1, 3]);
    });
  });

  group('refetchChapter', () {
    // chapterProvider is autoDispose: a bare ref.refresh() with nothing
    // listening tore it down mid-fetch and threw, leaving the row stale.
    testWidgets('survives the provider auto-disposing mid-fetch', (
      tester,
    ) async {
      late WidgetRef captured;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // Mirrors the real provider, which reads its repository off `ref`
            // after an async gap — that read is what throws once the provider
            // has been disposed out from under the fetch.
            chapterProvider(chapterId: 1).overrideWith((ref) async {
              await Future<void>.delayed(Duration.zero);
              ref.watch(_watchedAfterAsyncGap);
              return _fresh(id: 1, isRead: true);
            }),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              captured = ref;
              return const SizedBox();
            },
          ),
        ),
      );

      final pending = refetchChapter(captured, 1);
      await tester.pump(const Duration(milliseconds: 10));

      expect((await pending)?.isRead, isTrue);
    });

    testWidgets('a failing fetch still releases the provider', (tester) async {
      late WidgetRef captured;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chapterProvider(
              chapterId: 1,
            ).overrideWith((ref) async => throw Exception('server down')),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              captured = ref;
              return const SizedBox();
            },
          ),
        ),
      );

      Object? caught;
      await tester.runAsync(() async {
        try {
          await refetchChapter(captured, 1);
        } catch (e) {
          caught = e;
        }
      });

      // Completes rather than hanging, so the finally released the listener.
      expect(caught, isNotNull);
    });
  });

  group('Updates row refresh on return (#326)', () {
    testWidgets('opening the series from its cover refreshes the row on back', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();
      var refreshes = 0;

      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: ChapterMangaListTile(
                chapterWithMangaDto: _row(id: 1),
                updatePair: () async {},
                refreshManga: () async => refreshes++,
                toggleSelect: (_) {},
              ),
            ),
          ),
          GoRoute(
            path: '/manga/:mangaId',
            builder: (_, _) => const Scaffold(body: Text('details')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(sp),
            // The row's download icon and cover would otherwise open real
            // sockets from the test.
            graphQlClientProvider.overrideWithValue(
              GraphQLClient(
                link: HttpLink('http://localhost'),
                cache: GraphQLCache(),
              ),
            ),
          ],
          child: MaterialApp.router(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();

      // The cover's placeholder spinner never stops, so settle() would hang.
      await tester.tap(find.byType(ClipRRect).first, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('details'), findsOneWidget);

      router.pop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(refreshes, 1);
    });
  });
}
