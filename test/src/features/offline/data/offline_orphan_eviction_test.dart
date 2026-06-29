// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_sync.dart';

import '../../../../helpers/offline_test_db.dart';

ChapterDto serverChapter(int id) => Fragment$ChapterDto(
      id: id, mangaId: 1, name: 'c$id', chapterNumber: id.toDouble(),
      sourceOrder: id, isRead: false, isBookmarked: false, isDownloaded: true,
      lastPageRead: 0, pageCount: 30, fetchedAt: '0', uploadDate: '0',
      lastReadAt: '0', url: '', meta: const <Fragment$ChapterDto$meta>[],
    );

void main() {
  late OfflineDatabase db;
  setUp(() => db = testOfflineDatabase());
  tearDown(() => db.close());

  Future<void> downloaded(int id) =>
      db.into(db.offlineChapters).insert(OfflineChaptersCompanion.insert(
            id: Value(id), mangaId: 1, name: 'c$id', chapterIndex: id,
            updatedAt: DateTime(2026),
            deviceState: const Value(OfflineDeviceState.downloaded),
          ));

  test('syncChapters orphans a downloaded chapter the server no longer lists',
      () async {
    await downloaded(1);
    await downloaded(2);
    // The server now lists only chapter 1 — chapter 2 was deleted server-side.
    await OfflineSync(db).syncChapters([serverChapter(1)]);
    // Still on the server → kept.
    expect((await db.chapterById(1))!.deviceState,
        OfflineDeviceState.downloaded);
    // Gone from the server → orphaned so the next reconcile evicts it.
    expect(
        (await db.chapterById(2))!.deviceState, OfflineDeviceState.orphaned);
  });

  test('syncChapters does not orphan device chapters on an empty list',
      () async {
    await downloaded(1);
    await OfflineSync(db).syncChapters(const []); // failed/empty fetch
    expect(
        (await db.chapterById(1))!.deviceState, OfflineDeviceState.downloaded);
  });

  test('syncChapters does not orphan an in-flight (downloading) chapter',
      () async {
    await db.into(db.offlineChapters).insert(OfflineChaptersCompanion.insert(
          id: const Value(5), mangaId: 1, name: 'c5', chapterIndex: 5,
          updatedAt: DateTime(2026),
          deviceState: const Value(OfflineDeviceState.downloading),
        ));
    // Chapter 5 is gone from the server but mid-download — the background worker
    // owns it; orphaning/evicting it now would race the worker, which recreates
    // the row. Leave it to resolve on its own.
    await OfflineSync(db).syncChapters([serverChapter(1)]);
    expect((await db.chapterById(5))!.deviceState,
        OfflineDeviceState.downloading);
  });

  test('syncChapters keeps a device chapter the server lists but has not '
      'downloaded (device-on-demand, #32)', () async {
    await downloaded(1);
    // Server lists the chapter but reports it not downloaded server-side; the
    // device copy (served on demand) must NOT be orphaned.
    await OfflineSync(db).syncChapters([
      Fragment$ChapterDto(
        id: 1, mangaId: 1, name: 'c1', chapterNumber: 1, sourceOrder: 1,
        isRead: false, isBookmarked: false, isDownloaded: false,
        lastPageRead: 0, pageCount: 30, fetchedAt: '0', uploadDate: '0',
        lastReadAt: '0', url: '', meta: const <Fragment$ChapterDto$meta>[],
      ),
    ]);
    expect(
        (await db.chapterById(1))!.deviceState, OfflineDeviceState.downloaded);
  });
}
