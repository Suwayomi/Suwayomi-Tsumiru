// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:tsumiru/src/features/offline/data/account_storage_recovery.dart';
import 'package:tsumiru/src/features/offline/data/offline_bootstrap.dart';

import '../../helpers/offline_test_db.dart';

class _Support extends PathProviderPlatform {
  _Support(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'partial recovery merges real catalogues and reopens with preserved reset',
    () async {
      final support = await Directory.systemTemp.createTemp(
        'recovery-journey-',
      );
      PathProviderPlatform.instance = _Support(support.path);
      final legacy = (await initOfflineStorage())!;
      final root = legacy.paths.baseDir;
      await legacy.db.upsertMangaMetadata(
        id: 1,
        title: 'Saved manga',
        updatedAt: DateTime(2026),
      );
      await legacy.db.upsertChapterMetadata(
        id: 7,
        mangaId: 1,
        name: 'Chapter 7',
        chapterIndex: 1,
        isRead: false,
        lastPageRead: 0,
        isBookmarked: false,
        serverIsDownloaded: false,
        pageCount: 120,
        updatedAt: DateTime(2026),
      );
      await legacy.db.setChapterProgress(7, lastPageRead: 112);
      await legacy.db.close();
      final target = Directory(p.join(root, 'accounts', 'A'));
      await target.create(recursive: true);
      await File(
        p.join(root, 'catalog.sqlite'),
      ).copy(p.join(target.path, 'catalog.sqlite'));
      final changed = testOfflineDatabaseFile(
        p.join(target.path, 'catalog.sqlite'),
      );
      await changed.setChapterProgress(7, lastPageRead: 0, manual: true);
      await changed.upsertMangaMetadata(
        id: 2,
        title: 'Newer manga',
        updatedAt: DateTime(2026),
      );
      await changed.close();
      final originalPage = File(p.join(root, '1', '7', '000.jpg'));
      await originalPage.parent.create(recursive: true);
      await originalPage.writeAsBytes([1, 2, 3]);
      await expectLater(
        initOfflineStorage(
          accountId: 'A',
          legacyInstanceId: 'A',
          accountOwner: '2',
        ),
        throwsA(isA<AccountStorageRecoveryRequired>()),
      );
      await expectLater(
        initOfflineStorage(
          accountId: 'A',
          legacyInstanceId: 'A',
          accountOwner: '2',
          recovery: AccountStorageRecovery(
            isCurrent: () => true,
            onProgress: (_) {},
          ),
        ),
        throwsA(isA<AccountStorageProgressConflict>()),
      );
      expect(await originalPage.exists(), isTrue);
      final recovered = (await initOfflineStorage(
        accountId: 'A',
        legacyInstanceId: 'A',
        accountOwner: '2',
        recovery: AccountStorageRecovery(
          isCurrent: () => true,
          onProgress: (_) {},
          progressChoices: {7: false},
        ),
      ))!;
      expect(recovered.paths.baseDir, target.path);
      expect((await recovered.db.chapterById(7))!.lastPageRead, 0);
      expect((await recovered.db.chapterById(7))!.progressDirty, isTrue);
      expect((await recovered.db.mangaById(2))!.title, 'Newer manga');
      expect(
        await File(p.join(target.path, '1', '7', '000.jpg')).readAsBytes(),
        [1, 2, 3],
      );
      expect(await originalPage.exists(), isFalse);
      expect(await File(p.join(root, 'catalog.sqlite')).exists(), isFalse);
      await recovered.db.close();
      final reopened = (await initOfflineStorage(
        accountId: 'A',
        legacyInstanceId: 'A',
        accountOwner: '2',
      ))!;
      expect((await reopened.db.chapterById(7))!.lastPageRead, 0);
      await reopened.db.close();
    },
  );
}
