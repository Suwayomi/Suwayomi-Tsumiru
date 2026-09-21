// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tsumiru/src/features/offline/data/account_catalogue.dart';
import 'package:tsumiru/src/features/offline/data/account_catalogue_repository_io.dart';
import 'package:tsumiru/src/features/offline/data/account_storage_migration_io.dart';
import 'package:tsumiru/src/features/offline/data/account_storage_paths.dart';
import 'package:tsumiru/src/features/offline/data/background/background_download_lock.dart';

void main() {
  late Directory root;
  late SharedPreferences preferences;
  late NativeAccountCatalogueRepository repository;

  Future<Directory> catalogue(String id) async {
    final dir = Directory(p.join(root.path, 'accounts', id));
    await dir.create(recursive: true);
    await File(p.join(dir.path, accountStorageMarker)).writeAsString(id);
    await File(p.join(dir.path, '.account-owner')).writeAsString('2');
    await File(p.join(dir.path, 'catalog.sqlite')).writeAsBytes([1, 2, 3]);
    return dir;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('account-catalogue-test-');
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    repository = NativeAccountCatalogueRepository(root.path, preferences);
  });
  tearDown(() async => root.delete(recursive: true));

  test(
    'root catalogue listing and removal preserve nested accounts and shared controls',
    () async {
      final b = await catalogue('B');
      await File(p.join(root.path, '.account-root-id')).writeAsString('A');
      await File(p.join(root.path, '.account-owner')).writeAsString('2');
      await File(p.join(root.path, accountStorageMarker)).writeAsString('A');
      await File(p.join(root.path, 'catalog.sqlite')).writeAsBytes([1, 2, 3]);
      final page = File(p.join(root.path, '1', '7', '000.jpg'));
      await page.parent.create(recursive: true);
      await page.writeAsBytes([4, 5]);
      final control = File(p.join(root.path, 'admission.json'));
      await control.writeAsString('shared control');
      final rows = await repository.list(activePath: b.path);
      expect(rows.map((row) => row.id).toList(), ['A']);
      expect(rows.single.path, root.path);
      expect((await repository.list(activePath: root.path)).single.id, 'B');
      await repository.remove(rows.single, canRemove: () => true);
      expect(await page.exists(), isFalse);
      expect(await File(p.join(root.path, 'catalog.sqlite')).exists(), isFalse);
      expect(await File(p.join(b.path, 'catalog.sqlite')).readAsBytes(), [
        1,
        2,
        3,
      ]);
      expect(await control.readAsString(), 'shared control');
      expect(
        await File(p.join(root.path, '.account-root-id')).readAsString(),
        'A',
      );
      expect((await repository.list()).single.id, 'B');
    },
  );

  test(
    'lists non-account storage bytes and excludes its active path',
    () async {
      final target = Directory(nonAccountStoragePath(root.path));
      await target.create();
      await File(p.join(target.path, 'catalog.sqlite')).writeAsBytes([1, 2, 3]);
      final page = File(p.join(target.path, '1', '2', '0.jpg'));
      await page.parent.create(recursive: true);
      await page.writeAsBytes([4, 5]);
      await preferences.setString(offlineNonAccountCatalogServerIdKey, 'A');
      await preferences.setString(offlineNonAccountLastServerIdKey, 'A');
      await preferences.setString(
        offlineNonAccountLastServerAddressKey,
        'https://old.example',
      );
      final row = (await repository.list()).single;
      expect(row.isNonAccount, isTrue);
      expect(row.id, 'A');
      expect(row.address, 'https://old.example');
      expect(row.bytes, 5);
      await preferences.setString(
        offlineNonAccountLastServerIdKey,
        'different-server',
      );
      expect((await repository.list()).single.address, isNull);
      expect(await repository.list(activePath: target.path), isEmpty);
      await preferences.remove(offlineNonAccountCatalogServerIdKey);
      expect((await repository.list()).single.id, 'non-account');
    },
  );

  test(
    'removes only non-account data and its independent preferences',
    () async {
      final account = await catalogue('A');
      final target = Directory(nonAccountStoragePath(root.path));
      await target.create();
      await File(p.join(target.path, 'catalog.sqlite')).writeAsBytes([1, 2]);
      final rootData = File(p.join(root.path, 'catalog.sqlite'));
      await rootData.writeAsBytes([3, 4]);
      await preferences.setString(offlineNonAccountCatalogServerIdKey, 'A');
      await preferences.setString(offlineNonAccountLastServerIdKey, 'A');
      await preferences.setString(offlineNonAccountLastServerAddressKey, 'old');
      await preferences.setString('offlineCatalogServerId', 'A');
      await preferences.setString('account.current/A', '{}');
      await preferences.setInt('offlineCatchUpWatermark/A', 20);
      final row = (await repository.list()).firstWhere(
        (row) => row.isNonAccount,
      );
      await repository.remove(row, canRemove: () => true);
      expect(
        await File(p.join(target.path, 'catalog.sqlite')).exists(),
        isFalse,
      );
      expect(
        await File(p.join(target.path, '.bg_lock.sqlite')).exists(),
        isTrue,
      );
      expect(await File(p.join(root.path, '.bg_lock.sqlite')).exists(), isTrue);
      expect(
        await File(p.join(account.path, 'catalog.sqlite')).exists(),
        isTrue,
      );
      expect(await rootData.readAsBytes(), [3, 4]);
      expect(
        preferences.containsKey(offlineNonAccountCatalogServerIdKey),
        isFalse,
      );
      expect(
        preferences.containsKey(offlineNonAccountLastServerIdKey),
        isFalse,
      );
      expect(
        preferences.containsKey(offlineNonAccountLastServerAddressKey),
        isFalse,
      );
      expect(preferences.getString('offlineCatalogServerId'), 'A');
      expect(preferences.getString('account.current/A'), '{}');
      expect(preferences.getInt('offlineCatchUpWatermark/A'), 20);
      expect((await repository.list()).single.isNonAccount, isFalse);
    },
  );

  test(
    'removing unstamped non-account storage preserves the UI stamp',
    () async {
      final target = Directory(nonAccountStoragePath(root.path));
      await target.create();
      await File(p.join(target.path, 'catalog.sqlite')).writeAsBytes([1]);
      await preferences.setString('offlineCatalogServerId', 'ui-account');
      final row = (await repository.list()).single;
      expect(row.id, 'non-account');
      await repository.remove(row, canRemove: () => true);
      expect(preferences.getString('offlineCatalogServerId'), 'ui-account');
      expect(await repository.list(), isEmpty);
    },
  );

  test('non-account removal rejects a changed server stamp', () async {
    final target = Directory(nonAccountStoragePath(root.path));
    await target.create();
    final data = File(p.join(target.path, 'catalog.sqlite'));
    await data.writeAsBytes([1]);
    await preferences.setString(offlineNonAccountCatalogServerIdKey, 'A');
    final row = (await repository.list()).single;
    await preferences.setString(offlineNonAccountCatalogServerIdKey, 'B');
    await expectLater(
      repository.remove(row, canRemove: () => true),
      throwsStateError,
    );
    expect(await data.exists(), isTrue);
  });

  test(
    'non-account removal rejects stale admission, paths and symlinks',
    () async {
      final target = Directory(nonAccountStoragePath(root.path));
      await target.create();
      final data = File(p.join(target.path, 'catalog.sqlite'));
      await data.writeAsBytes([1]);
      final row = (await repository.list()).single;
      await expectLater(
        repository.remove(row, canRemove: () => false),
        throwsStateError,
      );
      var checks = 0;
      await expectLater(
        repository.remove(row, canRemove: () => ++checks == 1),
        throwsStateError,
      );
      expect(checks, 2);
      await expectLater(
        repository.remove(
          AccountCatalogue(
            id: row.id,
            owner: row.owner,
            path: root.path,
            bytes: 0,
            isNonAccount: true,
          ),
          canRemove: () => true,
        ),
        throwsStateError,
      );
      await Link(p.join(target.path, 'linked')).create(root.path);
      expect(await repository.list(), isEmpty);
      await expectLater(
        repository.remove(row, canRemove: () => true),
        throwsA(isA<FileSystemException>()),
      );
      expect(await data.exists(), isTrue);
    },
  );

  for (final targetLock in [false, true]) {
    test(
      'non-account removal respects ${targetLock ? 'target' : 'root'} lock',
      () async {
        final target = Directory(nonAccountStoragePath(root.path));
        await target.create();
        final data = File(p.join(target.path, 'catalog.sqlite'));
        await data.writeAsBytes([1]);
        final row = (await repository.list()).single;
        final lock = BackgroundDownloadLock(
          File(p.join(targetLock ? target.path : root.path, '.bg_lock')),
        );
        expect(await lock.acquire('test'), isTrue);
        try {
          await expectLater(
            repository.remove(row, canRemove: () => true),
            throwsStateError,
          );
          expect(await data.exists(), isTrue);
        } finally {
          await lock.release();
        }
      },
    );
  }

  for (final invalid in ['wrong-id', 'directory', 'symlink']) {
    test('rejects a cleared marker with $invalid', () async {
      final target = Directory(p.join(root.path, 'accounts', 'A'));
      await target.create(recursive: true);
      final marker = p.join(target.path, accountStorageClearedMarker);
      if (invalid == 'directory') {
        await Directory(marker).create();
      } else if (invalid == 'symlink') {
        await Link(marker).create(p.join(root.path, 'missing'));
      } else {
        await File(marker).writeAsString('B');
      }
      await expectLater(
        prepareAccountStorage(
          offlineRoot: root.path,
          instanceId: 'A',
          legacyInstanceId: 'A',
          accountOwner: '2',
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(
        await File(p.join(target.path, accountStorageMarker)).exists(),
        isFalse,
      );
    });
  }

  test(
    'a delayed lock holder sees the removed catalogue as incomplete',
    () async {
      final target = await catalogue('A');
      final lock = BackgroundDownloadLock(
        File(p.join(target.path, '.bg_lock')),
      );
      expect(await lock.acquire('worker-before-removal'), isTrue);
      await lock.release();
      final ready = Completer<void>();
      final worker = () async {
        await ready.future;
        expect(await lock.acquire('delayed-worker'), isTrue);
        try {
          expect(
            await accountStorageComplete(
              offlineRoot: root.path,
              instanceId: 'A',
            ),
            isFalse,
          );
          expect(
            await accountStorageCleared(
              offlineRoot: root.path,
              instanceId: 'A',
            ),
            isTrue,
          );
        } finally {
          await lock.release();
        }
      }();
      await repository.remove(
        (await repository.list()).single,
        canRemove: () => true,
      );
      expect(
        await File(p.join(target.path, '.bg_lock.sqlite')).exists(),
        isTrue,
      );
      ready.complete();
      await worker;
    },
  );

  test(
    'removed legacy downloads stay empty when the account returns',
    () async {
      final legacy = sqlite3.open(p.join(root.path, 'catalog.sqlite'));
      legacy.execute('CREATE TABLE saved_chapters (id INTEGER PRIMARY KEY)');
      legacy.execute('INSERT INTO saved_chapters VALUES (7)');
      legacy.close();
      final pages = Directory(p.join(root.path, '1', '7'));
      await pages.create(recursive: true);
      await File(p.join(pages.path, '0.jpg')).writeAsBytes([1, 2, 3]);
      final target = await prepareAccountStorage(
        offlineRoot: root.path,
        instanceId: 'A',
        legacyInstanceId: 'A',
        accountOwner: '2',
      );
      expect(await File(p.join(target, '1', '7', '0.jpg')).exists(), isTrue);
      await repository.remove(
        (await repository.list()).single,
        canRemove: () => true,
      );
      await prepareAccountStorage(
        offlineRoot: root.path,
        instanceId: 'A',
        legacyInstanceId: 'A',
        accountOwner: '2',
      );
      expect(await File(p.join(target, 'catalog.sqlite')).exists(), isFalse);
      expect(await Directory(p.join(target, '1')).exists(), isFalse);
      expect(await File(p.join(target, '.account-owner')).readAsString(), '2');
      expect(
        await accountStorageComplete(offlineRoot: root.path, instanceId: 'A'),
        isTrue,
      );
      expect(await File(p.join(root.path, 'catalog.sqlite')).exists(), isTrue);
      // Pages are moved into the account, not duplicated, so removing the
      // account's downloads removes them for real. Only the catalogue is
      // copied, because an interrupted move has to be able to resume.
      expect(await File(p.join(pages.path, '0.jpg')).exists(), isFalse);
    },
  );

  test(
    'lists inactive complete catalogues with labels and exact byte totals',
    () async {
      final a = await catalogue('A');
      await catalogue('B');
      await preferences.setString(
        'account.catalogue/A',
        jsonEncode({'username': 'reader', 'address': 'https://server.example'}),
      );
      await Directory(p.join(root.path, 'accounts', 'incomplete')).create();
      final rows = await repository.list(
        activePath: p.join(root.path, 'accounts', 'B'),
      );
      expect(rows.single.id, 'A');
      expect(rows.single.username, 'reader');
      expect(rows.single.address, 'https://server.example');
      var bytes = 0;
      await for (final item in a.list(recursive: true, followLinks: false)) {
        if (item is File) bytes += await item.length();
      }
      expect(rows.single.bytes, bytes);
    },
  );

  test('uses matching cached user and refuses symlink trees', () async {
    final a = await catalogue('A');
    await preferences.setString(
      'account.current/A',
      jsonEncode({
        'catalogId': 'A',
        'user': {'id': 2, 'username': 'cached'},
      }),
    );
    expect((await repository.list()).single.username, 'cached');
    await Link(p.join(a.path, 'linked')).create(root.path);
    expect(await repository.list(), isEmpty);
  });

  test(
    'removes target contents while preserving stable locks and other preferences',
    () async {
      final a = await catalogue('A');
      final b = await catalogue('B');
      await preferences.setString('account.current/A', '{}');
      await preferences.setInt('offlineCatchUpWatermark/A', 10);
      await preferences.setInt('offlineCatchUpWatermark/B', 20);
      await preferences.setBool('offlineDownloadsPaused', true);
      await preferences.setString('offline.downloadPermission/A', '{}');
      await preferences.setString('offline.downloadPermission/B', '{}');
      final target = (await repository.list()).firstWhere(
        (row) => row.id == 'A',
      );
      await repository.remove(target, canRemove: () => true);
      expect(await a.exists(), isTrue);
      expect(await File(p.join(a.path, '.bg_lock.sqlite')).exists(), isTrue);
      expect(
        await File(p.join(a.path, accountStorageMarker)).exists(),
        isFalse,
      );
      expect(await File(p.join(b.path, 'catalog.sqlite')).exists(), isTrue);
      expect(preferences.containsKey('account.current/A'), isFalse);
      expect(preferences.containsKey('offlineCatchUpWatermark/A'), isFalse);
      expect(preferences.getInt('offlineCatchUpWatermark/B'), 20);
      expect(preferences.getBool('offlineDownloadsPaused'), isTrue);
      expect(preferences.containsKey('offline.downloadPermission/A'), isFalse);
      expect(preferences.containsKey('offline.downloadPermission/B'), isTrue);
      expect((await repository.list()).single.id, 'B');
      expect(
        await prepareAccountStorage(
          offlineRoot: root.path,
          instanceId: 'A',
          accountOwner: '2',
        ),
        a.path,
      );
    },
  );

  test(
    'preserves permission lock controls while removing catalogue data',
    () async {
      final target = await catalogue('A');
      const controls = [
        '.bg_permission',
        '.bg_permission.sqlite',
        '.bg_permission.sqlite-journal',
        '.bg_permission.sqlite-wal',
        '.bg_permission.sqlite-shm',
        '.bg_permission.yield',
      ];
      for (final name in controls) {
        await File(p.join(target.path, name)).writeAsString(name);
      }
      await repository.remove(
        (await repository.list()).single,
        canRemove: () => true,
      );
      for (final name in controls) {
        expect(await File(p.join(target.path, name)).readAsString(), name);
      }
      expect(
        await File(p.join(target.path, 'catalog.sqlite')).exists(),
        isFalse,
      );
      expect(
        await prepareAccountStorage(
          offlineRoot: root.path,
          instanceId: 'A',
          accountOwner: '2',
        ),
        target.path,
      );
    },
  );

  test('rejects active or stale confirmation and changed owner', () async {
    final a = await catalogue('A');
    final target = (await repository.list()).single;
    await expectLater(
      repository.remove(target, canRemove: () => false),
      throwsStateError,
    );
    await File(p.join(a.path, '.account-owner')).writeAsString('3');
    await expectLater(
      repository.remove(target, canRemove: () => true),
      throwsStateError,
    );
    expect(await File(p.join(a.path, 'catalog.sqlite')).exists(), isTrue);
  });

  test(
    'rejects a symlink inserted after confirmation and rechecks admission under locks',
    () async {
      final a = await catalogue('A');
      final target = (await repository.list()).single;
      var checks = 0;
      await expectLater(
        repository.remove(target, canRemove: () => ++checks == 1),
        throwsStateError,
      );
      expect(checks, 2);
      await Link(p.join(a.path, 'linked')).create(root.path);
      await expectLater(
        repository.remove(target, canRemove: () => true),
        throwsA(isA<FileSystemException>()),
      );
      expect(await File(p.join(a.path, 'catalog.sqlite')).exists(), isTrue);
    },
  );

  for (final targetLock in [false, true]) {
    test('refuses ${targetLock ? 'target' : 'root'} lock contention', () async {
      final a = await catalogue('A');
      final target = (await repository.list()).single;
      final lock = BackgroundDownloadLock(
        File(p.join(targetLock ? a.path : root.path, '.bg_lock')),
      );
      expect(await lock.acquire('test'), isTrue);
      try {
        await expectLater(
          repository.remove(target, canRemove: () => true),
          throwsStateError,
        );
        expect(await File(p.join(a.path, 'catalog.sqlite')).exists(), isTrue);
      } finally {
        await lock.release();
      }
    });
  }
}
