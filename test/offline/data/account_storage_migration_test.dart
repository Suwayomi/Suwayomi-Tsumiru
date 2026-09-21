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

  test(
    'completed migration cleans verified originals without moving the account back',
    () async {
      legacy();
      final target = await prepareAccountStorage(
        offlineRoot: root.path,
        instanceId: 'a',
        legacyInstanceId: 'a',
      );
      final duplicate = File(p.join(root.path, '1/7/001.jpg'));
      await duplicate.parent.create(recursive: true);
      await File(p.join(target, '1/7/001.jpg')).copy(duplicate.path);
      final resumed = await prepareAccountStorage(
        offlineRoot: root.path,
        instanceId: 'a',
        legacyInstanceId: 'a',
        recovery: AccountStorageRecovery(
          isCurrent: () => true,
          onProgress: (_) {},
        ),
      );
      expect(resumed, target);
      expect(await duplicate.exists(), isFalse);
      expect(await File(p.join(root.path, 'catalog.sqlite')).exists(), isFalse);
      expect(
        await File(
          p.join(target, 'catalog.sqlite.legacy-recovery-backup'),
        ).exists(),
        isTrue,
      );
      expect(
        await File(p.join(target, 'catalog.sqlite.recovery-backup')).exists(),
        isTrue,
      );
      expect(
        await File(p.join(target, '1/7/001.jpg')).readAsString(),
        '1/7/001.jpg',
      );
      expect(
        await File(p.join(root.path, 'accounts/other/secret')).exists(),
        isTrue,
      );
      expect(await File(p.join(root.path, 'admission.json')).exists(), isTrue);
      expect(
        await prepareAccountStorage(
          offlineRoot: root.path,
          instanceId: 'a',
          legacyInstanceId: 'a',
        ),
        target,
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

  test(
    'matching legacy data moves with the catalogue and locks preserved',
    () async {
      legacy();
      final original = File(
        p.join(root.path, 'catalog.sqlite'),
      ).readAsBytesSync();
      var copied = 0;
      final target = await prepareAccountStorage(
        offlineRoot: root.path,
        instanceId: 'a',
        legacyInstanceId: 'a',
        copyFile: (source, destination) async {
          copied++;
          await source.copy(destination.path);
        },
      );
      expect(
        File(p.join(target, '1/8.part/.manifest')).readAsStringSync(),
        '1/8.part/.manifest',
      );
      expect(
        await accountStorageComplete(offlineRoot: root.path, instanceId: 'a'),
        isTrue,
      );
      for (final name in [
        'covers/1.jpg',
        '1/7/001.jpg',
        '1/8.part/001.jpg',
        '1/8.part/.manifest',
      ]) {
        expect(File(p.join(target, name)).readAsStringSync(), name);
        // Moved, so the chapter bytes were never read or rewritten.
        expect(
          FileSystemEntity.typeSync(p.join(root.path, name)),
          FileSystemEntityType.notFound,
          reason: name,
        );
      }
      // Only the catalogue is copied; it has to outlive an interrupted move.
      expect(copied, 1);
      expect(
        File(p.join(target, 'catalog.sqlite')).readAsBytesSync(),
        original,
      );
      expect(
        File(p.join(root.path, 'catalog.sqlite')).readAsBytesSync(),
        original,
      );
      expect(
        File(p.join(root.path, '.bg_lock.sqlite')).readAsStringSync(),
        '.bg_lock.sqlite',
      );
      for (final name in ['.bg_lock.sqlite', 'admission.json', 'accounts']) {
        expect(
          FileSystemEntity.typeSync(p.join(target, name)),
          FileSystemEntityType.notFound,
        );
      }
    },
  );

  test('a half-moved catalogue finishes without losing either side', () async {
    legacy();
    // What an interrupted migration leaves behind: some of the tree already at
    // the destination, the rest still at the root.
    final target = Directory(accountStoragePath(root.path, 'a'))
      ..createSync(recursive: true);
    final moved = File(p.join(target.path, 'covers/1.jpg'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('covers/1.jpg');
    Directory(p.join(root.path, 'covers')).deleteSync(recursive: true);

    final result = await prepareAccountStorage(
      offlineRoot: root.path,
      instanceId: 'a',
      legacyInstanceId: 'a',
    );

    expect(result, target.path);
    expect(moved.readAsStringSync(), 'covers/1.jpg');
    for (final name in ['1/7/001.jpg', '1/8.part/.manifest']) {
      expect(File(p.join(result, name)).readAsStringSync(), name);
    }
    expect(
      await accountStorageComplete(offlineRoot: root.path, instanceId: 'a'),
      isTrue,
    );
  });

  test(
    'resuming a partial migration preserves newer destination catalogue edits',
    () async {
      legacy();
      final target = Directory(accountStoragePath(root.path, 'a'))
        ..createSync(recursive: true);
      File(
        p.join(root.path, 'catalog.sqlite'),
      ).copySync(p.join(target.path, 'catalog.sqlite'));
      final newer = sqlite3.open(p.join(target.path, 'catalog.sqlite'));
      newer.execute('INSERT INTO chapters VALUES (112)');
      newer.close();
      await prepareAccountStorage(
        offlineRoot: root.path,
        instanceId: 'a',
        legacyInstanceId: 'a',
      );
      final reopened = sqlite3.open(p.join(target.path, 'catalog.sqlite'));
      try {
        expect(
          reopened
              .select('SELECT id FROM chapters ORDER BY id')
              .map((r) => r['id'])
              .toList(),
          [7, 112],
        );
      } finally {
        reopened.close();
      }
    },
  );

  test(
    'recovery replaces a truncated final page with its complete source',
    () async {
      legacy();
      final target = accountStoragePath(root.path, 'a');
      final existing = File(p.join(target, '1/7/001.jpg'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('1/7/');
      await prepareAccountStorage(
        offlineRoot: root.path,
        instanceId: 'a',
        legacyInstanceId: 'a',
      );
      expect(existing.readAsStringSync(), '1/7/001.jpg');
    },
  );

  test('recovery replaces an invalid truncated final catalogue', () async {
    legacy();
    final source = File(p.join(root.path, 'catalog.sqlite')).readAsBytesSync();
    final target = accountStoragePath(root.path, 'a');
    final existing = File(p.join(target, 'catalog.sqlite'))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(source.sublist(0, 1024));
    await prepareAccountStorage(
      offlineRoot: root.path,
      instanceId: 'a',
      legacyInstanceId: 'a',
    );
    final db = sqlite3.open(existing.path);
    try {
      expect(db.select('SELECT id FROM chapters').single['id'], 7);
    } finally {
      db.close();
    }
    expect(
      File('${existing.path}.truncated-backup').readAsBytesSync(),
      source.sublist(0, 1024),
    );
  });

  test('recovery replaces an empty final catalogue', () async {
    legacy();
    final target = accountStoragePath(root.path, 'a');
    final existing = File(p.join(target, 'catalog.sqlite'))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([]);
    await prepareAccountStorage(
      offlineRoot: root.path,
      instanceId: 'a',
      legacyInstanceId: 'a',
    );
    final db = sqlite3.open(existing.path);
    try {
      expect(db.select('SELECT id FROM chapters').single['id'], 7);
    } finally {
      db.close();
    }
  });

  test(
    'recovery preserves a corrupt catalogue that differs from the source',
    () async {
      legacy();
      final target = accountStoragePath(root.path, 'a');
      final existing = File(p.join(target, 'catalog.sqlite'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('different database bytes');
      await expectLater(
        prepareAccountStorage(
          offlineRoot: root.path,
          instanceId: 'a',
          legacyInstanceId: 'a',
        ),
        throwsA(isA<SqliteException>()),
      );
      expect(existing.readAsStringSync(), 'different database bytes');
      expect(File(p.join(root.path, 'catalog.sqlite')).existsSync(), isTrue);
    },
  );

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

  test('claimed root rejects a page symlink on reopen', () async {
    legacy();
    await claimRootAccountStorage(
      offlineRoot: root.path,
      instanceId: 'a',
      legacyInstanceId: 'a',
    );
    final page = File(p.join(root.path, '1/7/001.jpg'));
    page.deleteSync();
    Link(page.path).createSync(p.join(root.path, 'accounts/other/secret'));
    await expectLater(
      claimRootAccountStorage(
        offlineRoot: root.path,
        instanceId: 'a',
        legacyInstanceId: 'a',
      ),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('completed account rejects a page symlink on reopen', () async {
    legacy();
    final target = await prepareAccountStorage(
      offlineRoot: root.path,
      instanceId: 'a',
      legacyInstanceId: 'a',
    );
    final page = File(p.join(target, '1/7/001.jpg'));
    page.deleteSync();
    Link(page.path).createSync(p.join(root.path, 'accounts/other/secret'));
    await expectLater(
      prepareAccountStorage(offlineRoot: root.path, instanceId: 'a'),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('recovery does not overwrite a different existing page', () async {
    legacy();
    final target = Directory(accountStoragePath(root.path, 'a'))
      ..createSync(recursive: true);
    final existing = File(p.join(target.path, '1/7/001.jpg'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('newer page');
    await expectLater(
      prepareAccountStorage(
        offlineRoot: root.path,
        instanceId: 'a',
        legacyInstanceId: 'a',
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(existing.readAsStringSync(), 'newer page');
    expect(
      File(p.join(root.path, '1/7/001.jpg')).readAsStringSync(),
      '1/7/001.jpg',
    );
    expect(
      await accountStorageComplete(offlineRoot: root.path, instanceId: 'a'),
      isFalse,
    );
  });

  test('cancelled recovery leaves both locations resumable', () async {
    legacy();
    var current = true;
    await expectLater(
      prepareAccountStorage(
        offlineRoot: root.path,
        instanceId: 'a',
        legacyInstanceId: 'a',
        recovery: AccountStorageRecovery(
          isCurrent: () => current,
          onProgress: (_) => current = false,
        ),
      ),
      throwsStateError,
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
      File(p.join(target, 'covers/1.jpg')).readAsStringSync(),
      'covers/1.jpg',
    );
    expect(
      await accountStorageComplete(offlineRoot: root.path, instanceId: 'a'),
      isTrue,
    );
  });

  test('unstamped and other-account legacy data are never adopted', () async {
    legacy();
    for (final id in ['a', 'b']) {
      final target = await prepareAccountStorage(
        offlineRoot: root.path,
        instanceId: id,
        legacyInstanceId: id == 'a' ? null : 'other',
      );
      expect(File(p.join(target, 'catalog.sqlite')).existsSync(), isFalse);
      expect(
        await accountStorageComplete(offlineRoot: root.path, instanceId: id),
        isTrue,
      );
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
    Link(
      p.join(root.path, 'covers', 'linked'),
    ).createSync(p.join(root.path, '1'));
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
    Link(accountStoragePath(root.path, 'b')).createSync(elsewhere.path);
    await expectLater(
      prepareAccountStorage(offlineRoot: root.path, instanceId: 'b'),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('invalid copied database never receives a completion marker', () async {
    File(p.join(root.path, 'catalog.sqlite')).writeAsStringSync('not sqlite');
    await expectLater(
      prepareAccountStorage(
        offlineRoot: root.path,
        instanceId: 'a',
        legacyInstanceId: 'a',
      ),
      throwsA(isA<SqliteException>()),
    );
    expect(
      await accountStorageComplete(offlineRoot: root.path, instanceId: 'a'),
      isFalse,
    );
  });
  test('copy verification rejects changed bytes', () async {
    legacy();
    await expectLater(
      prepareAccountStorage(
        offlineRoot: root.path,
        instanceId: 'a',
        legacyInstanceId: 'a',
        renameEntity: _noRename,
        copyFile: (source, destination) async {
          final bytes = await source.readAsBytes();
          bytes[0] ^= 1;
          await destination.writeAsBytes(bytes);
        },
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(
      await accountStorageComplete(offlineRoot: root.path, instanceId: 'a'),
      isFalse,
    );
  });

  test('uncheckpointed legacy database is refused', () async {
    legacy();
    File(p.join(root.path, 'catalog.sqlite-wal')).writeAsStringSync('pending');
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
