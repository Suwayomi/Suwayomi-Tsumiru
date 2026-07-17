// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/widgets/chapter_grid_tile.dart';

GraphQLClient _dummyClient() => GraphQLClient(
      link: HttpLink('http://localhost:0'),
      cache: GraphQLCache(),
    );

class _RecordingRepo extends MangaBookRepository {
  _RecordingRepo() : super(_dummyClient());
  final List<(int, String, dynamic)> patched = [];
  @override
  Future<void> patchMangaMeta({
    required int mangaId,
    required String key,
    required dynamic value,
  }) async {
    patched.add((mangaId, key, value));
  }
}

class _FakeMangaWithId extends MangaWithId {
  @override
  Future<MangaDto?> build({required int mangaId}) async => null;
}

ChapterDto _chapter({double chapterNumber = 1, int sourceOrder = 1}) =>
    ChapterDto(
      chapterNumber: chapterNumber,
      fetchedAt: '0',
      id: 1,
      isBookmarked: false,
      isDownloaded: false,
      isRead: false,
      lastPageRead: 0,
      lastReadAt: '0',
      mangaId: 1,
      name: 'Chapter $chapterNumber',
      pageCount: 1,
      sourceOrder: sourceOrder,
      uploadDate: '0',
      url: '/chapter/1',
      meta: const [],
    );

void main() {
  group('MangaMeta.chapterListMode', () {
    test('parses the mode from the string-backed meta value', () {
      expect(
        MangaMeta.fromJson({'flutter_chapterListMode': 'grid'}).chapterListMode,
        ChapterListMode.grid,
      );
      expect(
        MangaMeta.fromJson({'flutter_chapterListMode': 'list'}).chapterListMode,
        ChapterListMode.list,
      );
    });
    test('is null when absent', () {
      expect(MangaMeta.fromJson(const {}).chapterListMode, isNull);
    });
  });

  group('mangaChapterListModeProvider', () {
    test('defaults to list when the series has no stored mode', () {
      final c = ProviderContainer(overrides: [
        mangaWithIdProvider(mangaId: 1).overrideWith(() => _FakeMangaWithId()),
      ]);
      addTearDown(c.dispose);
      expect(
        c.read(mangaChapterListModeProvider(mangaId: 1)),
        ChapterListMode.list,
      );
    });

    test('update persists the mode to the per-series meta store', () async {
      final repo = _RecordingRepo();
      final c = ProviderContainer(overrides: [
        mangaBookRepositoryProvider.overrideWithValue(repo),
        mangaWithIdProvider(mangaId: 1).overrideWith(() => _FakeMangaWithId()),
      ]);
      addTearDown(c.dispose);

      await c
          .read(mangaChapterListModeProvider(mangaId: 1).notifier)
          .update(ChapterListMode.grid);
      expect(repo.patched, contains((1, 'flutter_chapterListMode', 'grid')));

      await c
          .read(mangaChapterListModeProvider(mangaId: 1).notifier)
          .update(ChapterListMode.list);
      expect(repo.patched, contains((1, 'flutter_chapterListMode', 'list')));
    });
  });

  group('ChapterGridTile.label', () {
    test('whole chapter numbers drop the decimal point', () {
      expect(ChapterGridTile.label(_chapter(chapterNumber: 1145)), '1145');
    });
    test('fractional chapter numbers keep the decimal', () {
      expect(ChapterGridTile.label(_chapter(chapterNumber: 10.5)), '10.5');
    });
    test('unparsed chapter numbers fall back to source order', () {
      expect(
        ChapterGridTile.label(_chapter(chapterNumber: -1, sourceOrder: 12)),
        '#12',
      );
    });
  });
}
