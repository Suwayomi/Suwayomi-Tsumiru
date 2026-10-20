// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_read_fallback.dart';

import '../../../../helpers/offline_test_db.dart';

// A request that never errors (dead keep-alive socket, a Cloudflare edge with
// a dead origin) would otherwise hold a fallback-capable read through the
// full client timeout-and-retry window. With catalog data present, the fetch
// must be cut off at the fallback cap and the catalog served.
void main() {
  late OfflineDatabase db;
  setUp(() => db = testOfflineDatabase());
  tearDown(() => db.close());

  // A fetch that hangs forever — the airplane-mode/black-hole shape.
  Future<Never> hang() => Completer<Never>().future;

  Future<void> seedCatalog() async {
    await db.upsertMangaMetadata(id: 1, title: 'A', updatedAt: DateTime(2026));
    await db.upsertCategory(3, 'Shelf', 0, isHidden: false);
    await db.replaceMangaCategories(1, [3]);
    // The offline library only lists series with files on this device.
    await db.upsertChapterMetadata(
      id: 11,
      mangaId: 1,
      name: 'c1',
      chapterIndex: 1,
      isRead: false,
      lastPageRead: 0,
      isBookmarked: false,
      serverIsDownloaded: true,
      pageCount: 1,
      updatedAt: DateTime(2026),
    );
    await db.setChapterDeviceState(11, OfflineDeviceState.downloaded, bytes: 1);
  }

  test(
    'library: hanging fetch is cut at the cap and the catalog served',
    () async {
      await seedCatalog();
      final r = await libraryWithOfflineFallback(
        fetch: hang,
        db: db,
        offlineEnabled: true,
        fetchTimeout: const Duration(milliseconds: 50),
      );
      expect(r!.single.id, 1);
    },
  );
}
