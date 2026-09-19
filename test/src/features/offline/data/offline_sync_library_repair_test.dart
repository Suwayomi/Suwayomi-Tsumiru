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
  bookmarkCount: 0,
  chapters: Fragment$MangaDto$chapters(totalCount: 0),
  downloadCount: 0,
  genre: const [],
  inLibrary: inLibrary,
  inLibraryAt: inLibraryAt,
  initialized: true,
  meta: const [],
  source: null,
  sourceId: '1',
  status: Enum$MangaStatus.ONGOING,
  categories: Fragment$MangaDto$categories(nodes: const []),
  trackRecords: Fragment$MangaDto$trackRecords(totalCount: 0, nodes: const []),
  unreadCount: 0,
  updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
  url: '',
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

    test(
      'repairs a stranded removed-sentinel stamp even when the server\'s '
      'real value is literal "0" (manga predating the server tracking '
      'this field) — the sentinel is -1, not 0, so it no longer collides',
      () async {
        await seedManga(1, inLibraryAt: kLibraryRemovedSentinel);

        await OfflineSync(
          db,
        ).pruneRemovedLibraryManga([_serverManga(1, inLibraryAt: '0')]);

        expect(await inLibraryAtOf(1), '0');
        expect((await db.libraryManga()).map((m) => m.id), contains(1));
      },
    );

    test(
      'does not overwrite a real existing timestamp for present manga',
      () async {
        await seedManga(1, inLibraryAt: '1699000000000');

        await OfflineSync(db).pruneRemovedLibraryManga([
          _serverManga(1, inLibraryAt: '9999999999999'),
        ]);

        // Only removed-sentinel stamps are repaired; a real timestamp must not
        // be overwritten.
        expect(await inLibraryAtOf(1), '1699000000000');
      },
    );

    test('absent manga with no downloads is purged from the catalog', () async {
      await seedManga(1, inLibraryAt: '1699000000000');
      await seedManga(2, inLibraryAt: '1700000000000');

      // Only manga 1 is in the server library this sync.
      await OfflineSync(db).pruneRemovedLibraryManga([
        _serverManga(1, inLibraryAt: '1699000000000'),
      ]);

      // Manga 2 had no downloads, so it is deleted entirely after the
      // removed-sentinel stamp.
      expect(await inLibraryAtOf(2), isNull);
    });

    test('repair and stamp+purge happen together in one call', () async {
      await seedManga(
        1,
        inLibraryAt: kLibraryRemovedSentinel,
      ); // stranded — should be repaired
      await seedManga(2, inLibraryAt: '1700000000000'); // present — unchanged
      await seedManga(
        3,
        inLibraryAt: '1700000001000',
      ); // absent, no downloads — purged

      await OfflineSync(db).pruneRemovedLibraryManga([
        _serverManga(1, inLibraryAt: '1699000000000'),
        _serverManga(2, inLibraryAt: '1700000000000'),
      ]);

      expect(await inLibraryAtOf(1), '1699000000000'); // repaired
      expect(await inLibraryAtOf(2), '1700000000000'); // unchanged
      expect(await inLibraryAtOf(3), isNull); // stamped then purged
    });
  });

  group('libraryManga() after repair', () {
    test('returns manga whose removed-sentinel stamp was repaired', () async {
      // Manga with the removed sentinel is invisible to libraryManga().
      await seedManga(1, inLibraryAt: kLibraryRemovedSentinel);
      expect(await db.libraryManga(), isEmpty);

      await OfflineSync(db).pruneRemovedLibraryManga([
        _serverManga(1, inLibraryAt: '1699000000000'),
      ]);

      final library = await db.libraryManga();
      expect(library, hasLength(1));
      expect(library.first.id, 1);
    });
  });

  group('markNotInLibrary (unit)', () {
    test('stamps the removed sentinel on every manga not in the provided '
        'set', () async {
      await seedManga(1, inLibraryAt: '1699000000000');
      await seedManga(2, inLibraryAt: '1700000000000');

      await db.markNotInLibrary({1});

      expect(await inLibraryAtOf(1), '1699000000000'); // in set — untouched
      expect(
        await inLibraryAtOf(2),
        kLibraryRemovedSentinel,
      ); // not in set — stamped
    });
  });

  group('restoreLibraryTimestamps (unit)', () {
    test('only touches rows that carry the removed sentinel', () async {
      await seedManga(1, inLibraryAt: kLibraryRemovedSentinel);
      await seedManga(2, inLibraryAt: '1699000000000');

      await db.restoreLibraryTimestamps({
        1: '1699000000000',
        2: '9999999999999', // real timestamp — must be ignored
      });

      expect(await inLibraryAtOf(1), '1699000000000'); // repaired
      expect(await inLibraryAtOf(2), '1699000000000'); // untouched
    });

    test('null inLibraryAt rows are not overwritten', () async {
      await seedManga(1); // inLibraryAt: null (old row, pre-column)

      await db.restoreLibraryTimestamps({1: '1699000000000'});

      // null is not the removed sentinel, must stay null
      expect(await inLibraryAtOf(1), isNull);
    });
  });

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

    test(
      'a target with inLibrary: true is visible in libraryManga()',
      () async {
        await OfflineSync(db).syncManga(
          _serverManga(1, inLibraryAt: '1699000000000'),
          fetchedAtGen: db.syncGeneration,
        );

        expect(await inLibraryAtOf(1), '1699000000000');
        expect((await db.libraryManga()).map((m) => m.id), contains(1));
      },
    );
  });
}
