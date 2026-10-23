// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// ignore_for_file: prefer_const_constructors

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_sync.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

import '../../../../helpers/offline_test_db.dart';

// Minimal server-side MangaDto: only id, inLibrary and inLibraryAt matter
// for these tests.
Fragment$MangaDto _serverManga(
  int id, {
  required String inLibraryAt,
  bool inLibrary = true,
}) => Fragment$MangaDto(
  id: id,
  title: 'Manga $id',
  chapters: Fragment$MangaDto$chapters(totalCount: 0),
  genre: const [],
  initialized: true,
  meta: const [],
  source: null,
  sourceId: '1',
  status: Enum$MangaStatus.ONGOING,
  categories: Fragment$MangaDto$categories(nodes: const []),
  trackRecords: Fragment$MangaDto$trackRecords(nodes: const []),
  updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
  url: '',
  user: Fragment$MangaDto$user(
    bookmarkCount: 0,
    downloadCount: 0,
    inLibrary: inLibrary,
    inLibraryAt: inLibraryAt,
    unreadCount: 0,
  ),
);

void main() {
  late OfflineDatabase db;

  Future<void> seedManga(int id, {String? inLibraryAt}) =>
      db.upsertMangaMetadata(
        id: id,
        title: 'Manga $id',
        updatedAt: DateTime(2026),
        inLibraryAt: inLibraryAt,
      );

  Future<String?> inLibraryAtOf(int id) async {
    final row = await (db.select(
      db.offlineMangas,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row?.inLibraryAt;
  }

  setUp(() => db = testOfflineDatabase());
  tearDown(() => db.close());

  group('pruneRemovedLibraryManga', () {
    test('repairs a stranded removed-sentinel stamp with the real server '
        'timestamp', () async {
      // Manga 1: incorrectly stamped removed by a previous truncated-page
      // fetch.
      await seedManga(1, inLibraryAt: kLibraryRemovedSentinel);

      await OfflineSync(db).pruneRemovedLibraryManga([
        _serverManga(1, inLibraryAt: '1699000000000'),
      ]);

      expect(await inLibraryAtOf(1), '1699000000000');
    });
  });

  group('libraryManga() after repair', () {});

  group('markNotInLibrary (unit)', () {});

  group('restoreLibraryTimestamps (unit)', () {});

  group('syncManga', () {
    test('a target with inLibrary: false never becomes visible in '
        'libraryManga(), even with a real-looking inLibraryAt', () async {
      // Mirrors OfflineMigrationService.migrate(), which syncs a metadata
      // target that isn't necessarily in the caller's library.
      await OfflineSync(db).syncManga(
        _serverManga(1, inLibraryAt: '1699000000000', inLibrary: false),
        fetchedAtGen: db.syncGeneration,
      );

      expect(await inLibraryAtOf(1), kLibraryRemovedSentinel);
      expect(await db.libraryManga(), isEmpty);
    });
  });
}
