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
import 'package:tsumiru/src/features/offline/data/background/background_download_lock.dart';
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
  test('a busy worker defers recovery without holding startup', () async {
    final support = await Directory.systemTemp.createTemp('busy-storage-');
    PathProviderPlatform.instance = _Support(support.path);
    final lock = BackgroundDownloadLock(
      File(p.join(support.path, 'offline', '.bg_lock')),
    );
    expect(await lock.acquire('test-worker'), isTrue);
    addTearDown(lock.release);
    await expectLater(
      initOfflineStorage(accountId: 'A').timeout(const Duration(seconds: 2)),
      throwsA(isA<AccountStorageRecoveryRequired>()),
    );
    expect(await lock.yieldRequested(), isTrue);
  });
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
  test(
    'legacy owner keeps its files in place across account switches',
    () async {
      final support = await Directory.systemTemp.createTemp('claim-root-');
      PathProviderPlatform.instance = _Support(support.path);
      final legacy = (await initOfflineStorage())!;
      final original = legacy.paths.baseDir;
      await legacy.db.upsertMangaMetadata(
        id: 1,
        title: 'Saved',
        updatedAt: DateTime(2026),
      );
      final page = File(p.join(original, '1', '7', '000.jpg'));
      await page.parent.create(recursive: true);
      await page.writeAsBytes([1, 2, 3]);
      await legacy.db.close();
      final claimed = (await initOfflineStorage(
        accountId: 'A',
        legacyInstanceId: 'A',
        accountOwner: '2',
      ))!;
      addTearDown(claimed.db.close);
      expect(claimed.paths.baseDir, original);
      expect((await claimed.db.mangaById(1))?.title, 'Saved');
      expect(await page.readAsBytes(), [1, 2, 3]);
      expect(
        await File(
          p.join(original, 'accounts', 'A', 'catalog.sqlite'),
        ).exists(),
        isFalse,
      );
      await claimed.db.close();
      final other = (await initOfflineStorage(
        accountId: 'B',
        legacyInstanceId: 'A',
        accountOwner: '3',
      ))!;
      expect(await other.db.mangaById(1), isNull);
      await other.db.close();
      final returned = (await initOfflineStorage(
        accountId: 'A',
        legacyInstanceId: 'B',
        accountOwner: '2',
      ))!;
      expect(returned.paths.baseDir, original);
      expect((await returned.db.mangaById(1))?.title, 'Saved');
      await returned.db.close();
      await expectLater(
        initOfflineStorage(accountId: 'A', accountOwner: '3'),
        throwsStateError,
      );
      expect(await initOfflineStorage(), isNull);
    },
  );

  test(
    'startup defers a partial migration before moving download files',
    () async {
      final support = await Directory.systemTemp.createTemp('defer-storage-');
      PathProviderPlatform.instance = _Support(support.path);
      final legacy = (await initOfflineStorage())!;
      final root = legacy.paths.baseDir;
      await legacy.db.upsertMangaMetadata(
        id: 1,
        title: 'Legacy',
        updatedAt: DateTime(2026),
      );
      await legacy.db.close();
      final target = Directory(p.join(root, 'accounts', 'A'));
      await target.create(recursive: true);
      await File(
        p.join(root, 'catalog.sqlite'),
      ).copy(p.join(target.path, 'catalog.sqlite'));
      final page = File(p.join(root, '1', '7', '000.jpg'));
      await page.parent.create(recursive: true);
      await page.writeAsBytes([1, 2, 3]);
      await expectLater(
        initOfflineStorage(
          accountId: 'A',
          legacyInstanceId: 'A',
          accountOwner: '2',
        ).then((storage) => storage?.db.close()),
        throwsStateError,
      );
      expect(await page.readAsBytes(), [1, 2, 3]);
      expect(
        await File(p.join(target.path, '.account-complete')).exists(),
        isFalse,
      );
    },
  );

  test('a claimed root with a missing owner cannot be reassigned', () async {
    final support = await Directory.systemTemp.createTemp(
      'missing-root-owner-',
    );
    PathProviderPlatform.instance = _Support(support.path);
    final legacy = (await initOfflineStorage())!;
    await legacy.db.upsertMangaMetadata(
      id: 1,
      title: 'Private',
      updatedAt: DateTime(2026),
    );
    final root = legacy.paths.baseDir;
    await legacy.db.close();
    final claimed = (await initOfflineStorage(
      accountId: 'A',
      legacyInstanceId: 'A',
      accountOwner: '2',
    ))!;
    await claimed.db.close();
    await File(p.join(root, '.account-owner')).delete();
    await expectLater(
      initOfflineStorage(
        accountId: 'A',
        accountOwner: '3',
      ).then((storage) => storage?.db.close()),
      throwsStateError,
    );
  });

  test('a different user cannot open a reused catalogue identity', () async {
    final root = await Directory.systemTemp.createTemp('account-owner-');
    PathProviderPlatform.instance = _Support(root.path);
    final a = (await initOfflineStorage(
      accountId: 'shared-id',
      accountOwner: '1',
    ))!;
    await a.db.upsertMangaMetadata(
      id: 1,
      title: 'A',
      updatedAt: DateTime(2026),
    );
    await a.db.close();
    await expectLater(
      initOfflineStorage(accountId: 'shared-id', accountOwner: '2'),
      throwsStateError,
    );
    final restored = (await initOfflineStorage(
      accountId: 'shared-id',
      accountOwner: '1',
    ))!;
    expect((await restored.db.mangaById(1))?.title, 'A');
    await restored.db.close();
  });

  test(
    'native bootstrap preserves A data while opening B and returning to A',
    () async {
      final root = await Directory.systemTemp.createTemp('account-bootstrap-');
      PathProviderPlatform.instance = _Support(root.path);
      final a = (await initOfflineStorage(accountId: 'A'))!;
      await a.db.upsertMangaMetadata(
        id: 1,
        title: 'A',
        updatedAt: DateTime(2026),
      );
      await a.db.close();
      final b = (await initOfflineStorage(accountId: 'B'))!;
      expect(await b.db.mangaById(1), isNull);
      await b.db.close();
      final restored = (await initOfflineStorage(accountId: 'A'))!;
      expect((await restored.db.mangaById(1))?.title, 'A');
      await restored.db.close();
    },
  );
}
