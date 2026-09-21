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
  test('unclaimed Basic and no-auth downloads remain at root', () async {
    final support = await Directory.systemTemp.createTemp('unclaimed-root-');
    addTearDown(() => support.delete(recursive: true));
    PathProviderPlatform.instance = _Support(support.path);
    final original = (await initOfflineStorage())!;
    await original.db.upsertMangaMetadata(
      id: 1,
      title: 'Saved',
      updatedAt: DateTime(2026),
    );
    final page = File(p.join(original.paths.baseDir, '1', '7', '000.jpg'));
    await page.parent.create(recursive: true);
    await page.writeAsBytes([1, 2, 3]);
    await original.db.close();
    final reopened = (await initOfflineStorage(
      legacyInstanceId: 'basic-server',
    ))!;
    expect(reopened.paths.baseDir, p.join(support.path, 'offline'));
    expect((await reopened.db.mangaById(1))?.title, 'Saved');
    expect(await page.readAsBytes(), [1, 2, 3]);
    await reopened.db.close();
  });

  for (final nested in [false, true]) {
    test(
      'non-account storage refuses ${nested ? 'nested' : 'directory'} symlinks',
      () async {
        final support = await Directory.systemTemp.createTemp('no-auth-link-');
        addTearDown(() => support.delete(recursive: true));
        PathProviderPlatform.instance = _Support(support.path);
        final root = Directory(p.join(support.path, 'offline'));
        await root.create();
        await File(p.join(root.path, '.account-root-id')).writeAsString('A');
        final outside = Directory(p.join(support.path, 'outside'));
        await outside.create();
        final base = p.join(root.path, 'non-account');
        if (nested) await Directory(base).create();
        await Link(nested ? p.join(base, '1') : base).create(outside.path);
        await expectLater(
          initOfflineStorage(),
          throwsA(isA<FileSystemException>()),
        );
        expect(await outside.list().isEmpty, isTrue);
      },
    );
  }

  for (final atRoot in [true, false]) {
    test(
      'legacy UI Login owner upgrades to user 1 (${atRoot ? 'root' : 'scoped'})',
      () async {
        final support = await Directory.systemTemp.createTemp('legacy-owner-');
        addTearDown(() => support.delete(recursive: true));
        PathProviderPlatform.instance = _Support(support.path);
        if (atRoot) {
          final original = (await initOfflineStorage())!;
          await original.db.upsertMangaMetadata(
            id: 1,
            title: 'Saved manga',
            updatedAt: DateTime(2026),
          );
          await original.db.close();
        }
        final old = (await initOfflineStorage(
          accountId: 'A',
          legacyInstanceId: atRoot ? 'A' : null,
          accountOwner: 'legacy',
        ))!;
        await old.db.upsertMangaMetadata(
          id: 1,
          title: 'Saved manga',
          updatedAt: DateTime(2026),
        );
        final path = old.paths.baseDir;
        final page = File(p.join(path, '1', '7', '000.jpg'));
        await page.parent.create(recursive: true);
        await page.writeAsBytes([1, 2, 3]);
        await old.db.close();
        final owner = File(p.join(path, '.account-owner'));
        expect(await owner.readAsString(), 'legacy');
        await expectLater(
          initOfflineStorage(accountId: 'A', accountOwner: '2'),
          throwsStateError,
        );
        expect(await owner.readAsString(), 'legacy');
        final upgraded = (await initOfflineStorage(
          accountId: 'A',
          accountOwner: '1',
        ))!;
        expect(upgraded.paths.baseDir, path);
        expect(
          (await upgraded.db.select(upgraded.db.offlineMangas).get())
              .single
              .title,
          'Saved manga',
        );
        expect(await owner.readAsString(), '1');
        expect(await page.readAsBytes(), [1, 2, 3]);
        await upgraded.db.close();
        await expectLater(
          initOfflineStorage(accountId: 'A', accountOwner: 'legacy'),
          throwsStateError,
        );
        await expectLater(
          initOfflineStorage(accountId: 'A', accountOwner: '2'),
          throwsStateError,
        );
        expect(await owner.readAsString(), '1');
      },
    );
  }
  test('a busy worker can release storage without starting recovery', () async {
    final support = await Directory.systemTemp.createTemp('busy-storage-');
    PathProviderPlatform.instance = _Support(support.path);
    final lock = BackgroundDownloadLock(
      File(p.join(support.path, 'offline', '.bg_lock')),
    );
    expect(await lock.acquire('test-worker'), isTrue);
    addTearDown(lock.release);
    final opening = initOfflineStorage(accountId: 'A');
    final release = Future<void>.delayed(
      const Duration(milliseconds: 300),
      lock.release,
    );
    final storage = await opening.timeout(const Duration(seconds: 3));
    await release;
    expect(storage, isNotNull);
    await storage!.db.close();
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
      final noAuth = (await initOfflineStorage())!;
      final noAuthPath = noAuth.paths.baseDir;
      expect(noAuthPath, p.join(original, 'non-account'));
      expect(await noAuth.db.mangaById(1), isNull);
      expect(
        await File(p.join(noAuthPath, '1', '7', '000.jpg')).exists(),
        isFalse,
      );
      await noAuth.db.upsertMangaMetadata(
        id: 2,
        title: 'Basic download',
        updatedAt: DateTime(2026),
      );
      final basicPage = File(p.join(noAuthPath, '2', '8', '000.jpg'));
      await basicPage.parent.create(recursive: true);
      await basicPage.writeAsBytes([4, 5, 6]);
      await noAuth.db.close();
      final reopened = (await initOfflineStorage())!;
      expect(reopened.paths.baseDir, noAuthPath);
      expect((await reopened.db.mangaById(2))?.title, 'Basic download');
      expect(await basicPage.readAsBytes(), [4, 5, 6]);
      expect(await page.readAsBytes(), [1, 2, 3]);
      expect(await reopened.db.mangaById(1), isNull);
      await reopened.db.close();
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
