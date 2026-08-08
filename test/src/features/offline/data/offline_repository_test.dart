// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_paths.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';

import '../../../../helpers/offline_test_db.dart';

void main() {
  late OfflineRepository repo;
  setUp(() => repo = OfflineRepository(
        db: testOfflineDatabase(),
        paths: const OfflinePaths('/base/offline'),
      ));
  tearDown(() => repo.db.close());

  test('localPagePath resolves a stored page to an absolute path', () async {
    await repo.db.into(repo.db.offlinePages).insert(
          OfflinePagesCompanion.insert(
            chapterId: 2000,
            pageIndex: 0,
            relativePath: '552/2000/000.jpg',
          ),
        );
    expect(
      await repo.localPagePath(2000, 0),
      p.join('/base/offline', '552', '2000', '000.jpg'),
    );
  });

  test('localPagePath returns null for a page that is not downloaded', () async {
    expect(await repo.localPagePath(2000, 0), isNull);
  });

  test('keepRuleFor returns the manga keep-rule (off by default)', () async {
    await repo.db.upsertMangaMetadata(id: 5, title: 'M', updatedAt: DateTime(2026));
    expect(await repo.keepRuleFor(5), OfflineKeepRule.off);
    await repo.db.setKeepRule(5, OfflineKeepRule.all, 3);
    expect(await repo.keepRuleFor(5), OfflineKeepRule.all);
  });

  test('deviceDownloadedCount counts only downloaded device copies', () async {
    await repo.db.upsertChapterMetadata(
        id: 1,
        mangaId: 1,
        name: 'a',
        chapterIndex: 1,
        isRead: false,
        lastPageRead: 0,
        isBookmarked: false,
        serverIsDownloaded: true,
        pageCount: 1,
        updatedAt: DateTime(2026));
    await repo.db.upsertChapterMetadata(
        id: 2,
        mangaId: 1,
        name: 'b',
        chapterIndex: 2,
        isRead: false,
        lastPageRead: 0,
        isBookmarked: false,
        serverIsDownloaded: true,
        pageCount: 1,
        updatedAt: DateTime(2026));
    await repo.db.setChapterDeviceState(1, OfflineDeviceState.downloaded,
        bytes: 10);
    expect(await repo.deviceDownloadedCount([1, 2]), 1);
  });
}
