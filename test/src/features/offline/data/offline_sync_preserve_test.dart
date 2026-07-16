// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_sync.dart';

import '../../../../helpers/offline_test_db.dart';

ChapterDto chapterDto(
  int id, {
  required int lastPageRead,
  required bool isRead,
  bool isBookmarked = false,
}) =>
    Fragment$ChapterDto(
      id: id, mangaId: 1, name: 'c$id', chapterNumber: id.toDouble(),
      sourceOrder: id, isRead: isRead, isBookmarked: isBookmarked,
      isDownloaded: true, lastPageRead: lastPageRead, pageCount: 30,
      fetchedAt: '0', uploadDate: '0', lastReadAt: '0', url: '',
      meta: const <Fragment$ChapterDto$meta>[],
    );

void main() {
  late OfflineDatabase db;
  setUp(() => db = testOfflineDatabase());
  tearDown(() => db.close());

  Future<void> seedChapter(int id,
          {bool isRead = false, int lastPageRead = 0}) =>
      db.upsertChapterMetadata(
        id: id, mangaId: 1, name: 'c$id', chapterIndex: id, isRead: isRead,
        lastPageRead: lastPageRead, isBookmarked: false, serverIsDownloaded: true,
        pageCount: 30, updatedAt: DateTime(2026),
      );

  test('down-sync takes server isRead when only position is dirty', () async {
    await seedChapter(10); // clean row
    await db.setChapterProgress(10, lastPageRead: 5, isRead: null); // partial
    await OfflineSync(db)
        .syncChapters([chapterDto(10, lastPageRead: 0, isRead: true)]);
    final c = (await db.chapterById(10))!;
    expect(c.isRead, isTrue); // server's read-state accepted (was blocked)
    expect(c.lastPageRead, 5); // dirty position preserved
  });

  test('down-sync keeps a dirty local read-state, ignoring the server', () async {
    await seedChapter(10);
    await db.setChapterReadState(10, true); // marked read locally, not yet pushed
    await OfflineSync(db)
        .syncChapters([chapterDto(10, lastPageRead: 0, isRead: false)]);
    final c = (await db.chapterById(10))!;
    expect(c.isRead, isTrue); // local read-state kept, not clobbered
    expect(c.readStateDirty, isTrue); // still pending up-sync
  });
}
