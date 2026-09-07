import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:tsumiru/src/features/offline/data/account_storage_migration_io.dart';
import 'package:tsumiru/src/features/offline/data/account_storage_paths.dart';

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
    'matching legacy data is copied with source and locks preserved',
    () async {
      legacy();
      final original = File(
        p.join(root.path, 'catalog.sqlite'),
      ).readAsBytesSync();
      final target = await prepareAccountStorage(
        offlineRoot: root.path,
        instanceId: 'a',
        legacyInstanceId: 'a',
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
        'catalog.sqlite',
        'covers/1.jpg',
        '1/7/001.jpg',
        '1/8.part/001.jpg',
        '1/8.part/.manifest',
      ]) {
        expect(
          File(p.join(target, name)).readAsBytesSync(),
          File(p.join(root.path, name)).readAsBytesSync(),
        );
      }
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
