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

  test('account paths reject traversal and invalid identifiers, and '
      'symlinks are refused', () async {
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
}
