import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'account_storage_paths.dart';

const accountStorageMarker = '.account-complete';
const accountStorageClearedMarker = '.account-cleared';
typedef AccountFileCopy = Future<void> Function(File source, File destination);
typedef AccountEntityRename =
    Future<void> Function(FileSystemEntity source, String destination);

Future<bool> accountStorageComplete({
  required String offlineRoot,
  required String instanceId,
}) async {
  final target = accountStoragePath(offlineRoot, instanceId);
  await _checkAncestors(target, offlineRoot);
  final marker = File(p.join(target, accountStorageMarker));
  final type = await FileSystemEntity.type(marker.path, followLinks: false);
  if (type == FileSystemEntityType.notFound) return false;
  if (type != FileSystemEntityType.file) {
    throw FileSystemException('Invalid account completion marker', marker.path);
  }
  return await marker.readAsString() == instanceId;
}

Future<bool> accountStorageCleared({
  required String offlineRoot,
  required String instanceId,
}) async {
  final target = accountStoragePath(offlineRoot, instanceId);
  await _checkAncestors(target, offlineRoot);
  final marker = File(p.join(target, accountStorageClearedMarker));
  final type = await FileSystemEntity.type(marker.path, followLinks: false);
  if (type == FileSystemEntityType.notFound) return false;
  if (type != FileSystemEntityType.file ||
      await marker.readAsString() != instanceId) {
    throw FileSystemException('Invalid account cleared marker', marker.path);
  }
  return true;
}

// The caller must close the catalogue and hold exclusive worker ownership.
Future<String> prepareAccountStorage({
  required String offlineRoot,
  required String instanceId,
  String? legacyInstanceId,
  String? accountOwner,
  AccountFileCopy? copyFile,
  AccountEntityRename? renameEntity,
}) async {
  final target = Directory(accountStoragePath(offlineRoot, instanceId));
  await _checkAncestors(target.path, offlineRoot);
  await target.create(recursive: true);
  await _checkTree(target);
  final cleared = await accountStorageCleared(
    offlineRoot: offlineRoot,
    instanceId: instanceId,
  );
  if (accountOwner != null) {
    final owner = File(p.join(target.path, '.account-owner'));
    if (await owner.exists()) {
      if (await owner.readAsString() != accountOwner) {
        throw StateError('Catalogue belongs to a different account');
      }
    } else {
      if (await accountStorageComplete(
        offlineRoot: offlineRoot,
        instanceId: instanceId,
      )) {
        throw StateError('Catalogue owner is unknown');
      }
      await owner.writeAsString(accountOwner, flush: true);
    }
  }
  if (await accountStorageComplete(
    offlineRoot: offlineRoot,
    instanceId: instanceId,
  )) {
    return target.path;
  }
  final sourceDb = File(p.join(offlineRoot, 'catalog.sqlite'));
  final sourceType = await FileSystemEntity.type(
    sourceDb.path,
    followLinks: false,
  );
  final canResume =
      !cleared &&
      legacyInstanceId == instanceId &&
      sourceType != FileSystemEntityType.notFound;
  final hasAccountData = await target
      .list(followLinks: false)
      .any(
        (entry) => !const {
          '.bg_lock.sqlite',
          '.bg_lock.sqlite-journal',
          '.bg_lock.sqlite-wal',
          '.bg_lock.sqlite-shm',
          '.bg_lock.yield',
          '.bg_permission',
          '.bg_permission.sqlite',
          '.bg_permission.sqlite-journal',
          '.bg_permission.sqlite-wal',
          '.bg_permission.sqlite-shm',
          '.bg_permission.yield',
          '.account-owner',
          accountStorageClearedMarker,
        }.contains(p.basename(entry.path)),
      );
  if (!canResume && hasAccountData) {
    throw FileSystemException(
      'Incomplete account storage needs its legacy source',
      target.path,
    );
  }
  if (canResume) {
    if (sourceType != FileSystemEntityType.file) {
      throw FileSystemException('Invalid legacy catalogue', sourceDb.path);
    }
    final wal = File('${sourceDb.path}-wal');
    if (await wal.exists() && await wal.length() > 0) {
      throw FileSystemException(
        'Legacy catalogue needs a checkpoint',
        wal.path,
      );
    }
    await _copyVerified(
      sourceDb,
      File(p.join(target.path, 'catalog.sqlite')),
      copyFile,
    );
    await for (final entity in Directory(
      offlineRoot,
    ).list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (name != 'covers' && !RegExp(r'^[0-9]+$').hasMatch(name)) continue;
      if (entity is! Directory) {
        throw FileSystemException(
          'Invalid legacy storage directory',
          entity.path,
        );
      }
      await _moveDirectory(
        entity,
        Directory(p.join(target.path, name)),
        copyFile,
        renameEntity,
        offlineRoot,
      );
    }
    final database = sqlite3.open(
      p.join(target.path, 'catalog.sqlite'),
      mode: OpenMode.readOnly,
    );
    try {
      final rows = database.select('PRAGMA quick_check');
      if (rows.length != 1 || rows.single.values.single != 'ok') {
        throw FileSystemException(
          'Copied catalogue failed integrity check',
          target.path,
        );
      }
    } finally {
      database.close();
    }
  }
  final marker = File(p.join(target.path, accountStorageMarker));
  await marker.writeAsString(instanceId, flush: true);
  return target.path;
}

Future<void> _checkAncestors(String path, String root) async {
  var current = p.absolute(path);
  while (true) {
    final type = await FileSystemEntity.type(current, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.directory) {
      throw FileSystemException(
        'Account storage path is not a directory',
        current,
      );
    }
    if (current == p.absolute(root)) break;
    final parent = p.dirname(current);
    if (parent == current) break;
    current = parent;
  }
}

Future<void> _checkLegacyTree(Directory directory) async {
  await for (final entity in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is! Directory && entity is! File) {
      throw FileSystemException('Legacy storage contains a link', entity.path);
    }
  }
}

Future<void> _checkTree(Directory directory) async {
  await for (final entity in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is! Directory && entity is! File) {
      throw FileSystemException('Account storage contains a link', entity.path);
    }
  }
}

/// Both paths live under the same offline root, so a rename is a metadata
/// change and the chapter bytes never move. Copying an 11 GB catalogue and
/// verifying it byte by byte took over an hour and blocked the app behind a
/// splash screen. The copy below stays for the case a rename can't serve:
/// a destination that already holds a partial migration, or a root split
/// across devices.
Future<void> _moveDirectory(
  Directory source,
  Directory destination,
  AccountFileCopy? copyFile,
  AccountEntityRename? renameEntity,
  String offlineRoot,
) async {
  await _checkAncestors(destination.path, offlineRoot);
  // A rename adopts the subtree wholesale, so it has to be vetted first. The
  // per-entry walk below only sees what it copies.
  await _checkLegacyTree(source);
  if (await _renamed(source, destination.path, renameEntity)) return;
  await destination.create(recursive: true);
  await for (final entity in source.list(followLinks: false)) {
    final name = p.basename(entity.path);
    if (entity is! File && entity is! Directory) {
      throw FileSystemException('Legacy storage contains a link', entity.path);
    }
    final target = p.join(destination.path, name);
    if (entity is Directory) {
      await _moveDirectory(
        entity,
        Directory(target),
        copyFile,
        renameEntity,
        offlineRoot,
      );
    } else {
      await _moveFile(entity as File, File(target), copyFile, renameEntity);
    }
  }
}

Future<void> _moveFile(
  File source,
  File destination,
  AccountFileCopy? copyFile,
  AccountEntityRename? renameEntity,
) async {
  final type = await FileSystemEntity.type(
    destination.path,
    followLinks: false,
  );
  if (type != FileSystemEntityType.notFound &&
      type != FileSystemEntityType.file) {
    throw FileSystemException('Invalid account storage file', destination.path);
  }
  if (type == FileSystemEntityType.notFound &&
      await _renamed(source, destination.path, renameEntity)) {
    return;
  }
  await _copyVerified(source, destination, copyFile);
}

/// True when [source] now lives at [destination]. A rename onto an occupied
/// path, or across devices, fails and the caller copies instead.
Future<bool> _renamed(
  FileSystemEntity source,
  String destination,
  AccountEntityRename? renameEntity,
) async {
  if (await FileSystemEntity.type(destination, followLinks: false) !=
      FileSystemEntityType.notFound) {
    return false;
  }
  try {
    if (renameEntity != null) {
      await renameEntity(source, destination);
    } else {
      await source.rename(destination);
    }
    return true;
  } on FileSystemException {
    return false;
  }
}

Future<void> _copyVerified(
  File source,
  File destination,
  AccountFileCopy? copyFile,
) async {
  final type = await FileSystemEntity.type(
    destination.path,
    followLinks: false,
  );
  if (type != FileSystemEntityType.notFound &&
      type != FileSystemEntityType.file) {
    throw FileSystemException('Invalid account storage file', destination.path);
  }
  if (copyFile == null) {
    await source.copy(destination.path);
  } else {
    await copyFile(source, destination);
  }
  final input = await source.open();
  final output = await destination.open(mode: FileMode.append);
  try {
    if (await input.length() != await output.length()) {
      throw FileSystemException(
        'Account copy length differs',
        destination.path,
      );
    }
    await output.setPosition(0);
    while (true) {
      final before = await input.read(65536);
      if (before.isEmpty) break;
      final after = await output.read(before.length);
      for (var index = 0; index < before.length; index++) {
        if (index >= after.length || before[index] != after[index]) {
          throw FileSystemException('Account copy differs', destination.path);
        }
      }
    }
    await output.flush();
  } finally {
    await input.close();
    await output.close();
  }
}
