// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/offline/data/account_catalogue.dart';
import 'package:tsumiru/src/features/offline/data/account_catalogue_repository_io.dart';
import 'package:tsumiru/src/features/offline/data/account_storage_migration_io.dart';
import 'package:tsumiru/src/features/offline/data/account_storage_paths.dart';

import '../../../../helpers/test_link.dart';

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
      await createTestLink(p.join(target.path, 'linked'), root.path);
      expect(await repository.list(), isEmpty);
      await expectLater(
        repository.remove(row, canRemove: () => true),
        throwsA(isA<FileSystemException>()),
      );
      expect(await data.exists(), isTrue);
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
    await createTestLink(p.join(a.path, 'linked'), root.path);
    expect(await repository.list(), isEmpty);
  });
}
