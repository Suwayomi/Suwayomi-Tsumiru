// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'account_catalogue_recovery_io.dart';
import 'account_storage_paths.dart';
import 'account_storage_recovery.dart';

const rootAccountStorageMarker = '.account-root-id';

Future<void> _checkAccountOwner(File owner, String expectedOwner) async {
  final previous = await owner.readAsString();
  if (previous == expectedOwner) return;
  // Suwayomi's account migration assigns legacy data and metadata to user 1.
  if (previous != 'legacy' || expectedOwner != '1') {
    throw StateError('Catalogue belongs to a different account');
  }
  final pending = File('${owner.path}.pending');
  final type = await FileSystemEntity.type(pending.path, followLinks: false);
  if (type != FileSystemEntityType.notFound &&
      type != FileSystemEntityType.file) {
    throw FileSystemException(
      'Invalid account owner staging file',
      pending.path,
    );
  }
  await pending.writeAsString(expectedOwner, flush: true);
  await pending.rename(owner.path);
}

Future<String?> rootAccountStorageId(String offlineRoot) async {
  await _checkAncestors(offlineRoot, offlineRoot);
  final file = File(p.join(offlineRoot, rootAccountStorageMarker));
  final type = await FileSystemEntity.type(file.path, followLinks: false);
  if (type == FileSystemEntityType.notFound) return null;
  if (type != FileSystemEntityType.file) {
    throw FileSystemException('Invalid root account marker', file.path);
  }
  final id = await file.readAsString();
  accountStoragePath(offlineRoot, id);
  return id;
}

Future<String> resolvedAccountStoragePath(
  String offlineRoot,
  String instanceId,
) async {
  final target = accountStoragePath(offlineRoot, instanceId);
  return await rootAccountStorageId(offlineRoot) == instanceId
      ? offlineRoot
      : target;
}

Future<String?> claimRootAccountStorage({
  required String offlineRoot,
  required String instanceId,
  required String? legacyInstanceId,
  String? accountOwner,
}) async {
  final claimed = await rootAccountStorageId(offlineRoot);
  if (claimed != null && claimed != instanceId) return null;
  if (claimed == null) {
    if (legacyInstanceId != instanceId) return null;
    final target = accountStoragePath(offlineRoot, instanceId);
    await _checkAncestors(target, offlineRoot);
    if (await Directory(target).exists()) {
      final entries = await Directory(target).list(followLinks: false).toList();
      if (entries.any((entry) => !p.basename(entry.path).startsWith('.bg_'))) {
        return null;
      }
    }
    final source = File(p.join(offlineRoot, 'catalog.sqlite'));
    final type = await FileSystemEntity.type(source.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return null;
    if (type != FileSystemEntityType.file) {
      throw FileSystemException('Invalid legacy catalogue', source.path);
    }
  }
  final owner = File(p.join(offlineRoot, '.account-owner'));
  final ownerType = await FileSystemEntity.type(owner.path, followLinks: false);
  if (ownerType != FileSystemEntityType.notFound &&
      ownerType != FileSystemEntityType.file) {
    throw FileSystemException('Invalid catalogue owner', owner.path);
  }
  if (claimed != null && ownerType == FileSystemEntityType.notFound) {
    throw StateError('Catalogue owner is unknown');
  }
  for (final name in [
    'catalog.sqlite',
    'catalog.sqlite-wal',
    'catalog.sqlite-shm',
    'catalog.sqlite-journal',
  ]) {
    final path = p.join(offlineRoot, name);
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw FileSystemException('Invalid root catalogue', path);
    }
  }
  await for (final entity in Directory(offlineRoot).list(followLinks: false)) {
    final name = p.basename(entity.path);
    if (name != 'covers' && !RegExp(r'^[0-9]+$').hasMatch(name)) continue;
    if (entity is! Directory) {
      throw FileSystemException('Invalid root storage directory', entity.path);
    }
    await _checkTree(entity);
  }
  final expectedOwner = accountOwner ?? 'legacy';
  for (final name in [
    rootAccountStorageMarker,
    accountStorageMarker,
    accountStorageClearedMarker,
  ]) {
    final file = File(p.join(offlineRoot, name));
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw FileSystemException('Invalid account storage marker', file.path);
    }
    if (type == FileSystemEntityType.file &&
        await file.readAsString() != instanceId) {
      throw StateError('Root catalogue belongs to a different account');
    }
  }
  if (ownerType == FileSystemEntityType.file) {
    await _checkAccountOwner(owner, expectedOwner);
  }
  for (final entry in {
    '.account-owner': expectedOwner,
    rootAccountStorageMarker: instanceId,
    accountStorageMarker: instanceId,
  }.entries) {
    final file = File(p.join(offlineRoot, entry.key));
    if (await file.exists()) continue;
    final pending = File('${file.path}.pending');
    final type = await FileSystemEntity.type(pending.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw FileSystemException(
        'Invalid account marker staging file',
        pending.path,
      );
    }
    await pending.writeAsString(entry.value, flush: true);
    await pending.rename(file.path);
  }
  return offlineRoot;
}

const accountStorageMarker = '.account-complete';
const accountStorageClearedMarker = '.account-cleared';
typedef AccountFileCopy = Future<void> Function(File source, File destination);
typedef AccountEntityRename =
    Future<void> Function(FileSystemEntity source, String destination);

Future<bool> accountStorageComplete({
  required String offlineRoot,
  required String instanceId,
}) async {
  final target = await resolvedAccountStoragePath(offlineRoot, instanceId);
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
  final target = await resolvedAccountStoragePath(offlineRoot, instanceId);
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
  AccountStorageRecovery? recovery,
}) async {
  final worker = _AccountFileWorker(recovery);
  try {
    return await _prepareAccountStorage(
      offlineRoot: offlineRoot,
      instanceId: instanceId,
      legacyInstanceId: legacyInstanceId,
      accountOwner: accountOwner,
      copyFile: copyFile,
      renameEntity: renameEntity,
      recovery: recovery,
      worker: worker,
    );
  } finally {
    await worker.close();
  }
}

Future<String> _prepareAccountStorage({
  required String offlineRoot,
  required String instanceId,
  required _AccountFileWorker worker,
  String? legacyInstanceId,
  String? accountOwner,
  AccountFileCopy? copyFile,
  AccountEntityRename? renameEntity,
  AccountStorageRecovery? recovery,
}) async {
  final claimed = await rootAccountStorageId(offlineRoot);
  if (claimed == instanceId) {
    return (await claimRootAccountStorage(
      offlineRoot: offlineRoot,
      instanceId: instanceId,
      legacyInstanceId: legacyInstanceId,
      accountOwner: accountOwner,
    ))!;
  }
  final target = Directory(accountStoragePath(offlineRoot, instanceId));
  await _checkAncestors(target.path, offlineRoot);
  await target.create(recursive: true);
  final cleared = await accountStorageCleared(
    offlineRoot: offlineRoot,
    instanceId: instanceId,
  );
  if (accountOwner != null) {
    final owner = File(p.join(target.path, '.account-owner'));
    final type = await FileSystemEntity.type(owner.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw FileSystemException('Invalid catalogue owner', owner.path);
    }
    if (await owner.exists()) {
      await _checkAccountOwner(owner, accountOwner);
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
  final complete = await accountStorageComplete(
    offlineRoot: offlineRoot,
    instanceId: instanceId,
  );
  final cleanup =
      recovery != null &&
      legacyInstanceId == instanceId &&
      claimed == null &&
      !cleared &&
      await File(p.join(offlineRoot, 'catalog.sqlite')).exists();
  await _checkTree(target, recovery);
  if (complete && !cleanup) {
    for (final name in [
      'catalog.sqlite',
      'catalog.sqlite-wal',
      'catalog.sqlite-shm',
    ]) {
      final path = p.join(target.path, name);
      final type = await FileSystemEntity.type(path, followLinks: false);
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.file) {
        throw FileSystemException('Invalid account catalogue', path);
      }
    }
    return target.path;
  }
  final sourceDb = File(p.join(offlineRoot, 'catalog.sqlite'));
  final sourceType = await FileSystemEntity.type(
    sourceDb.path,
    followLinks: false,
  );
  final canResume =
      !cleared &&
      claimed == null &&
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
    final destinationDb = File(p.join(target.path, 'catalog.sqlite'));
    if (await destinationDb.exists() &&
        !_catalogueIsValid(destinationDb.path) &&
        await worker.run(sourceDb.path, destinationDb.path, 'prefix')) {
      // A valid catalogue or a nonmatching file may contain account changes.
      // Only an incomplete byte-for-byte copy can be replaced from the source.
      for (final suffix in ['-wal', '-shm', '-journal']) {
        final sidecar = File('${destinationDb.path}$suffix');
        if (await sidecar.exists() && await sidecar.length() != 0) {
          throw FileSystemException(
            'Partial catalogue has recovery data',
            sidecar.path,
          );
        }
      }
      final pending = File('${destinationDb.path}.copying');
      await _copyVerified(sourceDb, pending, copyFile, recovery, worker);
      if (!_catalogueIsValid(pending.path)) {
        throw FileSystemException(
          'Legacy catalogue failed integrity check',
          sourceDb.path,
        );
      }
      final backup = File('${destinationDb.path}.truncated-backup');
      final backupType = await FileSystemEntity.type(
        backup.path,
        followLinks: false,
      );
      if (backupType == FileSystemEntityType.notFound) {
        await destinationDb.rename(backup.path);
      } else if (backupType == FileSystemEntityType.file) {
        await worker.run(destinationDb.path, backup.path, 'verify');
      } else {
        throw FileSystemException(
          'Invalid truncated catalogue backup',
          backup.path,
        );
      }
      recovery?.check();
      await pending.rename(destinationDb.path);
    }
    if (!await destinationDb.exists()) {
      final pending = File('${destinationDb.path}.copying');
      await _copyVerified(sourceDb, pending, copyFile, recovery, worker);
      await pending.rename(destinationDb.path);
    }
    await reconcileAccountCatalogues(
      sourceDb.path,
      destinationDb.path,
      choices: recovery?.progressChoices ?? const {},
    );
    recovery?.check();
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
        recovery,
        worker,
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
  recovery?.check();
  await marker.writeAsString(instanceId, flush: true);
  if (canResume && recovery != null) {
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      final file = File('${sourceDb.path}$suffix');
      final type = await FileSystemEntity.type(file.path, followLinks: false);
      if (type == FileSystemEntityType.file) {
        await file.delete();
      } else if (type != FileSystemEntityType.notFound) {
        throw FileSystemException(
          'Invalid legacy catalogue sidecar',
          file.path,
        );
      }
    }
  }
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

Future<void> _checkLegacyTree(
  Directory directory,
  AccountStorageRecovery? recovery,
) async {
  await for (final entity in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    recovery?.check();
    if (entity is! Directory && entity is! File) {
      throw FileSystemException('Legacy storage contains a link', entity.path);
    }
  }
}

Future<void> _checkTree(
  Directory directory, [
  AccountStorageRecovery? recovery,
]) async {
  await for (final entity in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    recovery?.check();
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
  AccountStorageRecovery? recovery,
  _AccountFileWorker worker,
) async {
  recovery?.check();
  await _checkAncestors(destination.path, offlineRoot);
  // A rename adopts the subtree wholesale, so it has to be vetted first. The
  // per-entry walk below only sees what it copies.
  await _checkLegacyTree(source, recovery);
  if (await _renamed(source, destination.path, renameEntity)) {
    recovery?.completed();
    return;
  }
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
        recovery,
        worker,
      );
    } else {
      recovery?.check();
      await _moveFile(
        entity as File,
        File(target),
        copyFile,
        renameEntity,
        recovery,
        worker,
      );
      recovery?.completed();
    }
  }
}

Future<void> _moveFile(
  File source,
  File destination,
  AccountFileCopy? copyFile,
  AccountEntityRename? renameEntity,
  AccountStorageRecovery? recovery,
  _AccountFileWorker worker,
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
  if (type == FileSystemEntityType.file) {
    if (await worker.run(source.path, destination.path, 'prefix')) {
      final pending = File('${destination.path}.copying');
      await _copyVerified(source, pending, copyFile, recovery, worker);
      recovery?.check();
      await pending.rename(destination.path);
    } else {
      await worker.run(source.path, destination.path, 'verify');
    }
    recovery?.check();
    await source.delete();
    return;
  }
  final pending = File('${destination.path}.copying');
  await _copyVerified(source, pending, copyFile, recovery, worker);
  await pending.rename(destination.path);
  recovery?.check();
  await source.delete();
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
  AccountStorageRecovery? recovery,
  _AccountFileWorker worker,
) async {
  final type = await FileSystemEntity.type(
    destination.path,
    followLinks: false,
  );
  if (type != FileSystemEntityType.notFound &&
      type != FileSystemEntityType.file) {
    throw FileSystemException('Invalid account storage file', destination.path);
  }
  if (copyFile != null) {
    await copyFile(source, destination);
    recovery?.check();
  }
  await worker.run(
    source.path,
    destination.path,
    copyFile == null ? 'copy' : 'verify',
  );
}

bool _catalogueIsValid(String path) {
  if (File(path).lengthSync() == 0) return false;
  Database? database;
  try {
    database = sqlite3.open(path, mode: OpenMode.readOnly);
    final rows = database.select('PRAGMA quick_check');
    return rows.length == 1 && rows.single.values.single == 'ok';
  } on SqliteException {
    return false;
  } finally {
    database?.close();
  }
}

/// Requests are sequential, so one worker serves the whole migration.
class _AccountFileWorker {
  _AccountFileWorker(this.recovery);

  final AccountStorageRecovery? recovery;
  final ReceivePort _messages = ReceivePort();
  final Completer<SendPort> _ready = Completer<SendPort>();
  StreamSubscription<dynamic>? _subscription;
  Isolate? _isolate;
  Completer<bool>? _result;

  Object? _failure;
  StackTrace? _failureStack;

  Future<bool> run(String source, String destination, String operation) async {
    recovery?.check();
    if (_subscription == null) {
      _subscription = _messages.listen((message) {
        if (message is SendPort) {
          _ready.complete(message);
        } else if (message is bool) {
          _result?.complete(message);
        } else {
          final error = message is List
              ? message[0] as Object
              : StateError('Account file recovery stopped');
          final stack = message is List && message.length > 1
              ? message[1] is StackTrace
                    ? message[1] as StackTrace
                    : StackTrace.fromString('${message[1]}')
              : StackTrace.current;
          _failure = error;
          _failureStack = stack;
          if (!_ready.isCompleted) _ready.completeError(error, stack);
          if (_result != null && !_result!.isCompleted) {
            _result!.completeError(error, stack);
          }
        }
      });
      await Future.wait<void>([
        Isolate.spawn(
          _fileWorker,
          _messages.sendPort,
          onExit: _messages.sendPort,
          onError: _messages.sendPort,
        ).then((isolate) => _isolate = isolate),
        _ready.future.then((_) {}),
      ], eagerError: true);
    }
    if (_failure != null) Error.throwWithStackTrace(_failure!, _failureStack!);
    recovery?.check();
    final control = await _ready.future;
    _result = Completer<bool>();
    control.send((source, destination, operation));
    final cancellation = recovery == null
        ? null
        : Timer.periodic(const Duration(milliseconds: 20), (_) {
            if (!recovery!.isCurrent()) control.send(null);
          });
    try {
      final result = await _result!.future;
      recovery?.check();
      return result;
    } finally {
      cancellation?.cancel();
      _result = null;
    }
  }

  Future<void> close() async {
    _isolate?.kill(priority: Isolate.immediate);
    await _subscription?.cancel();
    _messages.close();
  }
}

void _fileWorker(SendPort result) {
  final commands = ReceivePort();
  var cancelled = false;
  void check() {
    if (cancelled) throw StateError('Account storage recovery cancelled');
  }

  commands.listen((message) async {
    if (message == null) {
      cancelled = true;
      return;
    }
    final (source, destination, operation) =
        message as (String, String, String);
    try {
      check();
      if (operation == 'prefix') {
        result.send(await _isTruncatedCopy(source, destination, check));
        return;
      }
      if (operation == 'copy') {
        final input = await File(source).open();
        try {
          final output = await File(destination).open(mode: FileMode.write);
          try {
            while (true) {
              check();
              final bytes = await input.read(65536);
              if (bytes.isEmpty) break;
              await output.writeFrom(bytes);
            }
            await output.flush();
          } finally {
            await output.close();
          }
        } finally {
          await input.close();
        }
      }
      check();
      await _verifyFileCopy(source, destination, check);
      result.send(true);
    } catch (error, stack) {
      result.send([error, stack]);
    }
  });
  result.send(commands.sendPort);
}

Future<bool> _isTruncatedCopy(
  String source,
  String destination,
  void Function() check,
) async {
  final input = await File(source).open();
  try {
    final output = await File(destination).open();
    try {
      if (await output.length() >= await input.length()) return false;
      while (true) {
        check();
        final after = await output.read(65536);
        if (after.isEmpty) return true;
        final before = await input.read(after.length);
        for (var i = 0; i < after.length; i++) {
          if (i >= before.length || before[i] != after[i]) return false;
        }
      }
    } finally {
      await output.close();
    }
  } finally {
    await input.close();
  }
}

Future<void> _verifyFileCopy(
  String sourcePath,
  String destinationPath,
  void Function() check,
) async {
  final input = await File(sourcePath).open();
  try {
    final output = await File(destinationPath).open();
    try {
      if (await input.length() != await output.length()) {
        throw FileSystemException(
          'Account copy length differs',
          destinationPath,
        );
      }
      while (true) {
        check();
        final before = await input.read(65536);
        if (before.isEmpty) break;
        final after = await output.read(before.length);
        for (var index = 0; index < before.length; index++) {
          if (index >= after.length || before[index] != after[index]) {
            throw FileSystemException('Account copy differs', destinationPath);
          }
        }
      }
    } finally {
      await output.close();
    }
  } finally {
    await input.close();
  }
}
