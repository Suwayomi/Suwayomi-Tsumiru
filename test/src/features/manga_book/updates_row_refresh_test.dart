// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter_batch/chapter_batch_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/updates/updates_row_patch.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/controller/reader_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/updates/updates_screen.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/features/offline/data/offline_read_fallback.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

import '../../../helpers/offline_test_db.dart';

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

/// Stands in for the server being unreachable.
class _OfflineRepo extends MangaBookRepository {
  _OfflineRepo()
    : super(
        GraphQLClient(
          link: HttpLink('http://localhost:0'),
          cache: GraphQLCache(),
        ),
      );

  @override
  Future<void> putChapter({
    required int chapterId,
    required ChapterChange patch,
  }) async => throw Exception('connection refused');
}

Future<void> _putChapter(
  OfflineDatabase db, {
  required int id,
  bool isRead = false,
}) => db.upsertChapterMetadata(
  id: id,
  mangaId: _kMangaId,
  name: 'Chapter $id',
  chapterIndex: id,
  isRead: isRead,
  lastPageRead: 0,
  isBookmarked: false,
  serverIsDownloaded: true,
  pageCount: 10,
  updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
);

/// What the Updates screen does on return, with the server down.
Future<List<ChapterDto>> _refreshOffline(OfflineDatabase db, List<int> ids) =>
    fetchChaptersInBatches(
      ids: ids,
      fetch: (id) => chapterMetaWithOfflineFallback(
        fetch: () async => throw Exception('connection refused'),
        db: db,
        offlineEnabled: true,
        offlineFirst: true,
        chapterId: id,
      ),
    );

void main() {
  test('a chapter read with the server down greys its row', () async {
    final db = testOfflineDatabase();
    addTearDown(db.close);
    await _putChapter(db, id: 1);
    await _putChapter(db, id: 2);

    // Read chapter 1 to the end, offline. This is the same call the reader
    // makes; the server write fails and the on-device catalog carries it.
    await recordReadingProgressWithDependencies(
      offlineEnabled: true,
      offlineDatabase: db,
      repository: _OfflineRepo(),
      chapterId: 1,
      lastPageRead: 9,
      isRead: true,
    );

    final chapters = await _refreshOffline(db, [1, 2]);
    final rows = patchRowsForManga(
      rows: [_row(id: 1), _row(id: 2)],
      mangaId: _kMangaId,
      chapters: chapters,
    );

    expect(rows.map((e) => e.isRead), [true, false]);
  });

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

    test('a lagging refetch cannot un-read a row', () {
      final patched = patchRowsForManga(
        rows: [_row(id: 1, isRead: true)],
        mangaId: _kMangaId,
        chapters: [_fresh(id: 1)],
      );

      expect(patched.single.isRead, isTrue);
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
}
