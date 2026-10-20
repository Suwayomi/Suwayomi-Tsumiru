// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:tsumiru/src/features/offline/data/account_storage_migration_io.dart';
import 'package:tsumiru/src/features/offline/data/account_storage_paths.dart';
import 'package:tsumiru/src/features/offline/data/account_storage_recovery.dart';

import '../../helpers/test_link.dart';

/// Forces the copy fallback: a rename that behaves as if the destination
/// sat on another device.
Future<void> _noRename(FileSystemEntity source, String destination) async =>
    throw const FileSystemException('cross-device');

void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('account-storage-');
  });
  tearDown(() => root.deleteSync(recursive: true));

  void legacy() {
    final db = sqlite3.open(p.join(root.path, 'catalog.sqlite'));
    db.execute('CREATE TABLE chapters (id INTEGER PRIMARY KEY)');
    db.execute('INSERT INTO chapters VALUES (7)');
    db.close();
    for (final name in [
      'covers/1.jpg',
      '1/7/001.jpg',
      '1/8.part/001.jpg',
      '1/8.part/.manifest',
      '.bg_lock.sqlite',
      'admission.json',
      'accounts/other/secret',
    ]) {
      final file = File(p.join(root.path, name));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(name);
    }
  }

  test(
    'cancellation interrupts a large copy and preserves the original',
    () async {
      legacy();
      final source = File(p.join(root.path, '1/7/001.jpg'));
      final handle = await source.open(mode: FileMode.append);
      await handle.truncate(256 * 1024 * 1024);
      await handle.close();
      final target = accountStoragePath(root.path, 'legacy');
      final pending = File(p.join(target, '1/7/001.jpg.copying'));
      var copyingObserved = false;
      final recovery = AccountStorageRecovery(
        isCurrent: () {
          if (pending.existsSync() && pending.lengthSync() > 0) {
            copyingObserved = true;
          }
          return !copyingObserved;
        },
        onProgress: (_) {},
      );
      await expectLater(
        prepareAccountStorage(
          offlineRoot: root.path,
          instanceId: 'legacy',
          legacyInstanceId: 'legacy',
          renameEntity: _noRename,
          recovery: recovery,
        ),
        throwsStateError,
      );
      expect(copyingObserved, isTrue);
      expect(await source.length(), 256 * 1024 * 1024);
      expect(await pending.length(), lessThan(await source.length()));
      expect(File(p.join(target, '1/7/001.jpg')).existsSync(), isFalse);
      expect(
        await accountStorageComplete(
          offlineRoot: root.path,
          instanceId: 'legacy',
        ),
        isFalse,
      );
    },
  );

  test('account paths reject traversal and invalid identifiers', () {
    for (final id in [
      '',
      '..',
      '../other',
      '/root',
      'a/b',
      r'a\b',
      '.hidden',
      'ä',
      '-abc',
      'a' * 129,
    ]) {
      expect(() => accountStoragePath(root.path, id), throwsArgumentError);
    }
    expect(
      accountStoragePath(root.path, 'User_12-test'),
      p.join(root.path, 'accounts', 'User_12-test'),
    );
  });

  test('copy fallback completes a directory containing many pages', () async {
    legacy();
    for (var i = 2; i <= 300; i++) {
      File(p.join(root.path, '1/7/$i.jpg')).writeAsStringSync('page $i');
    }
    final target = await prepareAccountStorage(
      offlineRoot: root.path,
      instanceId: 'a',
      legacyInstanceId: 'a',
      renameEntity: _noRename,
    );
    for (var i = 2; i <= 300; i++) {
      expect(File(p.join(target, '1/7/$i.jpg')).readAsStringSync(), 'page $i');
    }
  });

  test('interrupted copy resumes without changing source', () async {
    legacy();
    var copies = 0;
    await expectLater(
      prepareAccountStorage(
        offlineRoot: root.path,
        instanceId: 'a',
        legacyInstanceId: 'a',
        renameEntity: _noRename,
        copyFile: (source, destination) async {
          if (++copies == 2) throw const FileSystemException('interrupted');
          await source.copy(destination.path);
        },
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(
      await accountStorageComplete(offlineRoot: root.path, instanceId: 'a'),
      isFalse,
    );
    final target = await prepareAccountStorage(
      offlineRoot: root.path,
      instanceId: 'a',
      legacyInstanceId: 'a',
    );
    expect(
      File(p.join(target, '1/7/001.jpg')).readAsStringSync(),
      '1/7/001.jpg',
    );
    expect(
      await accountStorageComplete(offlineRoot: root.path, instanceId: 'a'),
      isTrue,
    );
  });

  test('wrong and empty markers cannot claim completion', () async {
    final target = Directory(accountStoragePath(root.path, 'a'))
      ..createSync(recursive: true);
    for (final value in ['', 'b']) {
      File(p.join(target.path, accountStorageMarker)).writeAsStringSync(value);
      expect(
        await accountStorageComplete(offlineRoot: root.path, instanceId: 'a'),
        isFalse,
      );
    }
  });

  test('source and destination symlinks are refused', () async {
    legacy();
    createTestLinkSync(
      p.join(root.path, 'covers', 'linked'),
      p.join(root.path, '1'),
    );
    await expectLater(
      prepareAccountStorage(
        offlineRoot: root.path,
        instanceId: 'a',
        legacyInstanceId: 'a',
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(
      await accountStorageComplete(offlineRoot: root.path, instanceId: 'a'),
      isFalse,
    );
    final elsewhere = Directory(p.join(root.path, 'elsewhere'))..createSync();
    createTestLinkSync(accountStoragePath(root.path, 'b'), elsewhere.path);
    await expectLater(
      prepareAccountStorage(offlineRoot: root.path, instanceId: 'b'),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('partial migration requires its matching source to resume', () async {
    legacy();
    var copies = 0;
    await expectLater(
      prepareAccountStorage(
        offlineRoot: root.path,
        instanceId: 'a',
        legacyInstanceId: 'a',
        renameEntity: _noRename,
        copyFile: (source, destination) async {
          if (++copies == 2) throw const FileSystemException('interrupted');
          await source.copy(destination.path);
        },
      ),
      throwsA(isA<FileSystemException>()),
    );
    for (final owner in <String?>[null, 'other']) {
      await expectLater(
        prepareAccountStorage(
          offlineRoot: root.path,
          instanceId: 'a',
          legacyInstanceId: owner,
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(
        await accountStorageComplete(offlineRoot: root.path, instanceId: 'a'),
        isFalse,
      );
    }
    await File(
      p.join(root.path, 'catalog.sqlite'),
    ).rename(p.join(root.path, 'saved-catalog.sqlite'));
    await expectLater(
      prepareAccountStorage(
        offlineRoot: root.path,
        instanceId: 'a',
        legacyInstanceId: 'a',
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(
      await accountStorageComplete(offlineRoot: root.path, instanceId: 'a'),
      isFalse,
    );
  });

  test('completed account can reopen without its legacy source', () async {
    legacy();
    final target = await prepareAccountStorage(
      offlineRoot: root.path,
      instanceId: 'a',
      legacyInstanceId: 'a',
    );
    expect(
      await prepareAccountStorage(offlineRoot: root.path, instanceId: 'a'),
      target,
    );
  });
}
