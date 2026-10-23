// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/updates/updates_row_patch.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/controller/reader_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/updates/updates_screen.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

const _kMangaId = 7;

final _watchedAfterAsyncGap = Provider<int>((ref) => 1);

Fragment$MangaBaseDto _manga({int id = _kMangaId}) => Fragment$MangaBaseDto(
  id: id,
  genre: const [],
  initialized: true,
  meta: const [],
  sourceId: '1',
  status: Enum$MangaStatus.ONGOING,
  thumbnailUrl: '/thumb/$id',
  title: 'Series $id',
  updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
  url: '/manga/$id',
  user: Fragment$MangaBaseDto$user(
    inLibrary: true,
    inLibraryAt: '0',
    unreadCount: 3,
  ),
);

ChapterWithMangaDto _row({required int id, bool isRead = false}) =>
    Fragment$ChapterWithMangaDto(
      id: id,
      chapterNumber: id.toDouble(),
      fetchedAt: '0',
      mangaId: _kMangaId,
      name: 'Chapter $id',
      pageCount: 10,
      sourceOrder: id,
      uploadDate: '0',
      url: '/c/$id',
      meta: const [],
      manga: _manga(),
      user: Fragment$ChapterWithMangaDto$user(
        isBookmarked: false,
        isDownloaded: false,
        isRead: isRead,
        lastPageRead: 0,
        lastReadAt: '0',
      ),
    );

ChapterDto _fresh({required int id, bool isRead = false}) =>
    Fragment$ChapterDto(
      id: id,
      chapterNumber: id.toDouble(),
      fetchedAt: '0',
      mangaId: _kMangaId,
      name: 'Chapter $id',
      pageCount: 10,
      sourceOrder: id,
      uploadDate: '0',
      url: '/c/$id',
      meta: const [],
      user: Fragment$ChapterDto$user(
        isBookmarked: false,
        isDownloaded: false,
        isRead: isRead,
        lastPageRead: 0,
        lastReadAt: '0',
      ),
    );

void main() {
  group('patchRowsForManga', () {
    test('a lagging refetch cannot un-read a row', () {
      final patched = patchRowsForManga(
        rows: [_row(id: 1, isRead: true)],
        mangaId: _kMangaId,
        chapters: [_fresh(id: 1)],
      );

      expect(patched.single.user.isRead, isTrue);
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
            chapterProvider(chapterId: 1).overrideWithBuild((ref, _) async {
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

      expect((await pending)?.user.isRead, isTrue);
    });
  });
}
