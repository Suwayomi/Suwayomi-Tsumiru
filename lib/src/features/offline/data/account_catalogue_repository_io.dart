// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../constants/db_keys.dart';
import 'account_catalogue.dart';
import 'account_storage_migration_io.dart';
import 'background/background_download_lock.dart';

Future<AccountCatalogueRepository> createAccountCatalogueRepository(
  SharedPreferences preferences,
) async => NativeAccountCatalogueRepository(
  p.join((await getApplicationSupportDirectory()).path, 'offline'),
  preferences,
);

class NativeAccountCatalogueRepository implements AccountCatalogueRepository {
  NativeAccountCatalogueRepository(this.root, this.preferences);

  final String root;
  final SharedPreferences preferences;
  static const _locks = {
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
  };

  Future<bool> _directory(String path) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return false;
    if (type != FileSystemEntityType.directory) {
      throw FileSystemException('Invalid catalogue directory', path);
    }
    return true;
  }

  Future<List<FileSystemEntity>> _tree(String path) async {
    final entries = <FileSystemEntity>[];
    Stream<FileSystemEntity> entriesAt(String directory) async* {
      await for (final entry in Directory(directory).list(followLinks: false)) {
        final name = p.basename(entry.path);
        if (p.equals(path, root) &&
            p.equals(directory, root) &&
            name != 'covers' &&
            !RegExp(r'^[0-9]+$').hasMatch(name) &&
            !{
              'catalog.sqlite',
              'catalog.sqlite-wal',
              'catalog.sqlite-journal',
              'catalog.sqlite-shm',
              accountStorageMarker,
              accountStorageClearedMarker,
              '.account-owner',
              rootAccountStorageMarker,
            }.contains(name)) {
          continue;
        }
        yield entry;
        if (entry is Directory) yield* entriesAt(entry.path);
      }
    }

    await for (final entry in entriesAt(path)) {
      if (entry is! File && entry is! Directory) {
        throw FileSystemException('Invalid catalogue entry', entry.path);
      }
      if (p.dirname(entry.path) == path &&
          _locks.contains(p.basename(entry.path)) &&
          entry is! File) {
        throw FileSystemException('Invalid catalogue lock', entry.path);
      }
      entries.add(entry);
    }
    return entries;
  }

  Future<String> _owner(String id) async {
    if (!await accountStorageComplete(offlineRoot: root, instanceId: id)) {
      throw StateError('Catalogue is incomplete');
    }
    final file = File(
      p.join(await resolvedAccountStoragePath(root, id), '.account-owner'),
    );
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw FileSystemException('Invalid catalogue owner', file.path);
    }
    final owner = await file.readAsString();
    if (owner != 'legacy' && (int.tryParse(owner) ?? 0) <= 0) {
      throw StateError('Invalid catalogue owner');
    }
    return owner;
  }

  Map<String, dynamic> _metadata(String key) {
    try {
      return jsonDecode(preferences.getString(key) ?? '{}')
          as Map<String, dynamic>;
    } on Object {
      return {};
    }
  }

  @override
  Future<List<AccountCatalogue>> list({String? activePath}) async {
    final accounts = p.join(root, 'accounts');
    if (!await _directory(root)) return [];
    final rootId = await rootAccountStorageId(root);
    final candidates = <FileSystemEntity>[
      if (rootId != null) Directory(root),
      if (await _directory(accounts))
        ...await Directory(accounts).list(followLinks: false).toList(),
    ];
    final result = <AccountCatalogue>[];
    for (final directory in candidates) {
      if (directory is! Directory ||
          (activePath != null && p.equals(directory.path, activePath))) {
        continue;
      }
      try {
        final id = p.equals(directory.path, root)
            ? rootId!
            : p.basename(directory.path);
        if (!p.equals(
          directory.path,
          await resolvedAccountStoragePath(root, id),
        )) {
          continue;
        }
        final owner = await _owner(id);
        final entries = await _tree(directory.path);
        var bytes = 0;
        for (final file in entries.whereType<File>()) {
          bytes += await file.length();
        }
        final metadata = _metadata('account.catalogue/$id');
        final cached = _metadata('account.current/$id');
        final user = cached['user'];
        final storedUsername = metadata['username'];
        final cachedUsername =
            cached['catalogId'] == id && user is Map && '${user['id']}' == owner
            ? user['username']
            : null;
        final username = storedUsername is String && storedUsername.isNotEmpty
            ? storedUsername
            : cachedUsername is String && cachedUsername.isNotEmpty
            ? cachedUsername
            : null;
        final address = metadata['address'];
        result.add(
          AccountCatalogue(
            id: id,
            owner: owner,
            path: directory.path,
            bytes: bytes,
            username: username,
            address: address is String && address.isNotEmpty ? address : null,
          ),
        );
      } on Object {
        continue;
      }
    }
    result.sort((a, b) => a.id.compareTo(b.id));
    return result;
  }

  @override
  Future<void> remove(
    AccountCatalogue catalogue, {
    required bool Function() canRemove,
  }) async {
    final target = await resolvedAccountStoragePath(root, catalogue.id);
    if (!p.equals(target, catalogue.path) || !canRemove()) {
      throw StateError('Catalogue is active or the session changed');
    }
    if (await _owner(catalogue.id) != catalogue.owner) {
      throw StateError('Catalogue owner changed');
    }
    await _tree(target);
    for (final name in _locks) {
      final path = p.join(root, name);
      final type = await FileSystemEntity.type(path, followLinks: false);
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.file) {
        throw FileSystemException('Invalid catalogue lock', path);
      }
    }
    final held = <BackgroundDownloadLock>[];
    try {
      for (final path in {root, target}) {
        final lock = BackgroundDownloadLock(File(p.join(path, '.bg_lock')));
        if (!await lock.acquire('remove-catalogue')) {
          throw StateError('Catalogue is in use');
        }
        held.add(lock);
      }
      if (!canRemove() || await _owner(catalogue.id) != catalogue.owner) {
        throw StateError('Catalogue is active or the session changed');
      }
      final entries = await _tree(target);
      if (!canRemove()) throw StateError('Authentication session changed');
      await accountStorageCleared(offlineRoot: root, instanceId: catalogue.id);
      await File(
        p.join(target, accountStorageClearedMarker),
      ).writeAsString(catalogue.id, flush: true);
      final rootCatalogue = p.equals(target, root);
      final markers = {
        accountStorageMarker,
        if (!rootCatalogue) '.account-owner',
      };
      final retained = {
        rootAccountStorageMarker,
        if (rootCatalogue) '.account-owner',
      };
      final data =
          entries
              .where(
                (entry) =>
                    p.dirname(entry.path) != target ||
                    (!_locks.contains(p.basename(entry.path)) &&
                        !markers.contains(p.basename(entry.path)) &&
                        !retained.contains(p.basename(entry.path)) &&
                        p.basename(entry.path) != accountStorageClearedMarker),
              )
              .toList()
            ..sort((a, b) => b.path.length.compareTo(a.path.length));
      for (final entry in data) {
        final type = await FileSystemEntity.type(
          entry.path,
          followLinks: false,
        );
        if ((entry is File && type != FileSystemEntityType.file) ||
            (entry is Directory && type != FileSystemEntityType.directory)) {
          throw FileSystemException('Catalogue entry changed', entry.path);
        }
        await entry.delete();
      }
      for (final name in markers) {
        await File(p.join(target, name)).delete();
      }
      final keys = {
        'account.catalogue/${catalogue.id}',
        'account.current/${catalogue.id}',
        '${DBKeys.offlineCatchUpWatermark.name}/${catalogue.id}',
        '${DBKeys.offlineCatchUpAwaitingPull.name}/${catalogue.id}',
        'offlinePhantomCleanupDone/${catalogue.id}',
        'offline.downloadPermission/${catalogue.id}',
        'catchup_ledger/${catalogue.id}',
        if (_metadata('catchup_ledger')['serverId'] == catalogue.id)
          'catchup_ledger',
      };
      for (final key in preferences.getKeys().intersection(keys)) {
        if (!await preferences.remove(key)) {
          throw StateError('Could not remove catalogue metadata');
        }
      }
    } finally {
      for (final lock in held.reversed) {
        await lock.release();
      }
    }
  }
}
