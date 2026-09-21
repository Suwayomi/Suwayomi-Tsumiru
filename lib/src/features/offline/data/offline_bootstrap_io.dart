// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'account_storage_migration_io.dart';
import 'account_storage_paths.dart';
import 'account_storage_recovery.dart';
import 'background/background_download_lock.dart';
import 'offline_database.dart';
import 'offline_page_store.dart';
import 'offline_page_store_io.dart';
import 'offline_paths.dart';

/// Native (mobile + desktop) implementation: open the drift catalog on a file
/// under the app-support directory, plus the dart:io page store.
Future<({OfflineDatabase db, OfflinePaths paths, OfflinePageStore store})?>
openOfflineStorage({
  String? accountId,
  String? legacyInstanceId,
  String? ownedRoot,
  String? accountOwner,
  AccountStorageRecovery? recovery,
}) async {
  final support = await getApplicationSupportDirectory();
  final root = p.join(support.path, 'offline');
  final locks = <BackgroundDownloadLock>[];
  try {
    var baseDir = root;
    if (accountId == null && await rootAccountStorageId(root) != null) {
      baseDir = nonAccountStoragePath(root);
      await _checkNonAccountStorage(Directory(baseDir));
    }
    if (accountId != null) {
      final target = accountStoragePath(root, accountId);
      await accountStorageComplete(offlineRoot: root, instanceId: accountId);
      for (final directory in {root, target}) {
        if (directory == ownedRoot) continue;
        for (final name in [
          '.bg_lock.sqlite',
          '.bg_lock.sqlite-journal',
          '.bg_lock.sqlite-wal',
          '.bg_lock.sqlite-shm',
        ]) {
          final path = p.join(directory, name);
          final type = await FileSystemEntity.type(path, followLinks: false);
          if (type != FileSystemEntityType.notFound &&
              type != FileSystemEntityType.file) {
            throw FileSystemException('Invalid account storage lock', path);
          }
        }
        final lock = BackgroundDownloadLock(
          File(p.join(directory, '.bg_lock')),
        );
        var acquired = await lock.acquire('account-storage');
        for (var attempt = 0; !acquired && attempt < 300; attempt++) {
          recovery?.check();
          await lock.requestYield();
          await Future<void>.delayed(const Duration(milliseconds: 100));
          acquired = await lock.acquire('account-storage');
        }
        if (!acquired) {
          throw StateError('Downloads did not release account storage');
        }
        locks.add(lock);
      }
      final claimedRoot = await claimRootAccountStorage(
        offlineRoot: root,
        instanceId: accountId,
        legacyInstanceId: legacyInstanceId,
        accountOwner: accountOwner,
      );
      if (claimedRoot == null &&
          legacyInstanceId == accountId &&
          !await accountStorageCleared(
            offlineRoot: root,
            instanceId: accountId,
          )) {
        final source = File(p.join(root, 'catalog.sqlite'));
        final type = await FileSystemEntity.type(
          source.path,
          followLinks: false,
        );
        if (type == FileSystemEntityType.file) {
          if (recovery == null) throw AccountStorageRecoveryRequired();
          recovery.check();
          for (final suffix in ['-wal', '-shm']) {
            final sidecarType = await FileSystemEntity.type(
              '${source.path}$suffix',
              followLinks: false,
            );
            if (sidecarType != FileSystemEntityType.notFound &&
                sidecarType != FileSystemEntityType.file) {
              throw FileSystemException(
                'Invalid catalogue sidecar',
                '${source.path}$suffix',
              );
            }
          }
          final database = sqlite3.open(source.path, mode: OpenMode.readWrite);
          try {
            final result = database.select('PRAGMA wal_checkpoint(TRUNCATE)');
            if (result.single.values.first != 0) {
              throw StateError('Catalogue checkpoint is busy');
            }
          } finally {
            database.close();
          }
        }
      }
      baseDir =
          claimedRoot ??
          await prepareAccountStorage(
            offlineRoot: root,
            instanceId: accountId,
            legacyInstanceId: legacyInstanceId,
            accountOwner: accountOwner,
            recovery: recovery,
          );
    }
    await Directory(baseDir).create(recursive: true);
    final paths = OfflinePaths(baseDir);
    final db = OfflineDatabase(
      NativeDatabase.createInBackground(
        File(p.join(baseDir, 'catalog.sqlite')),
      ),
    );
    return (db: db, paths: paths, store: IoOfflinePageStore(paths));
  } finally {
    for (final lock in locks.reversed) {
      await lock.release();
    }
  }
}

Future<bool> accountStorageWasCleared(OfflinePaths paths) async {
  if (isNonAccountStoragePath(paths.baseDir)) return false;
  final root = offlineControlRoot(paths.baseDir);
  final id = root == paths.baseDir
      ? await rootAccountStorageId(root)
      : p.basename(paths.baseDir);
  return id != null &&
      await accountStorageCleared(offlineRoot: root, instanceId: id);
}

Future<void> _checkNonAccountStorage(Directory directory) async {
  final type = await FileSystemEntity.type(directory.path, followLinks: false);
  if (type == FileSystemEntityType.notFound) return;
  if (type != FileSystemEntityType.directory) {
    throw FileSystemException(
      'Invalid offline storage directory',
      directory.path,
    );
  }
  await for (final entry in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entry is! File && entry is! Directory) {
      throw FileSystemException('Invalid offline storage entry', entry.path);
    }
  }
}
