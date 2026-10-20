// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// The per-manga chapter sort reaches the offline keep-window only through
// OfflineMangas.chapterSortMode.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_dto_mappers.dart';
import 'package:tsumiru/src/features/offline/data/offline_sync.dart';

import '../../../../helpers/offline_test_db.dart';

void main() {
  late OfflineDatabase db;
  late MangaDto manga;

  setUp(() async {
    db = testOfflineDatabase();
    await db.upsertMangaMetadata(
      id: 1,
      title: 'M',
      updatedAt: DateTime(2026),
      inLibraryAt: '1',
    );
    manga = offlineMangaToDto((await db.mangaById(1))!);
  });
  tearDown(() => db.close());

  Future<ChapterSortAxis?> mirroredAxis(Map<String, String> meta) async {
    await OfflineSync(db).syncManga(
      manga.copyWith(
        meta: [
          for (final e in meta.entries)
            Fragment$MangaDto$meta(key: e.key, value: e.value),
        ],
      ),
      fetchedAtGen: db.syncGeneration,
    );
    return (await db.mangaById(1))!.chapterSortMode;
  }

  group('OfflineSync mirrors the manga\'s sort axis for the keep-window', () {
    test('the alphabetical flag wins over the webUI_sortBy it leaves in '
        'place, so downloads follow the order the reader shows', () async {
      expect(
        await mirroredAxis({
          'flutter_chapterSortIsAlphabetical': 'true',
          'webUI_sortBy': 'chapterNumber',
        }),
        ChapterSortAxis.alphabetical,
      );
    });
  });
}
