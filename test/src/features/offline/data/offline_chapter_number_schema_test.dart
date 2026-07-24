// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_dto_mappers.dart';

import '../../../../helpers/offline_test_db.dart';

void main() {
  late OfflineDatabase db;
  setUp(() => db = testOfflineDatabase());
  tearDown(() => db.close());

  Future<OfflineChapter> upsert({
    required int id,
    double? number,
    String? scanlator,
  }) async {
    await db.upsertChapterMetadata(
      id: id,
      mangaId: 1,
      name: 'c$id',
      chapterIndex: id,
      isRead: false,
      lastPageRead: 0,
      isBookmarked: false,
      serverIsDownloaded: false,
      pageCount: 3,
      updatedAt: DateTime(2026),
      chapterNumber: number,
      scanlator: scanlator,
    );
    return (db.select(db.offlineChapters)..where((t) => t.id.equals(id)))
        .getSingle();
  }

  test('chapterNumber and scanlator persist through the upsert', () async {
    final c = await upsert(id: 10, number: 9.5, scanlator: 'Nyx Scans');
    expect((c.chapterNumber, c.scanlator), (9.5, 'Nyx Scans'));
  });

  test('mapper prefers the real number and carries the scanlator', () async {
    final c = await upsert(id: 11, number: 2, scanlator: 'A');
    final dto = offlineChapterToDto(c);
    expect((dto.chapterNumber, dto.scanlator, dto.sourceOrder), (2.0, 'A', 11));
  });

  test('mapper falls back to the index for pre-v9 rows (null number)',
      () async {
    final c = await upsert(id: 12);
    final dto = offlineChapterToDto(c);
    expect((dto.chapterNumber, dto.scanlator), (12.0, null));
  });
}
