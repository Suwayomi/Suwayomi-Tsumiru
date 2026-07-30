// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:file/file.dart' hide FileSystem;
import 'package:file/local.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Cover/icon image cache that survives OS cache pressure.
///
/// The default cache manager keeps at most 200 files in the OS *temp* dir —
/// shared with reader pages, so reading a few chapters evicts most library
/// covers, and Android (or a Linux reboot) wipes the dir wholesale. Offline
/// mode renders covers purely from this cache, so losing it turns the offline
/// library into a wall of broken images.
///
/// Covers are small and long-lived, so they get their own store: files under
/// application-support (durable, app-private) with a cap sized to a large
/// library instead of a page ring buffer.
CacheManager createCoverCacheManager() => CacheManager(
      Config(
        'tsumiruCovers',
        stalePeriod: const Duration(days: 90),
        maxNrOfCacheObjects: 5000,
        fileSystem: _AppSupportFileSystem('tsumiruCovers'),
      ),
    );

/// Same layout as the package's IOFileSystem, but rooted in
/// application-support instead of the OS temp dir.
class _AppSupportFileSystem implements FileSystem {
  _AppSupportFileSystem(this._cacheKey) : _fileDir = _createDirectory(_cacheKey);

  final Future<Directory> _fileDir;
  final String _cacheKey;

  static Future<Directory> _createDirectory(String key) async {
    final baseDir = await getApplicationSupportDirectory();
    final directory =
        const LocalFileSystem().directory(p.join(baseDir.path, key));
    await directory.create(recursive: true);
    return directory;
  }

  @override
  Future<File> createFile(String name) async {
    final directory = await _fileDir;
    if (!(await directory.exists())) {
      await _createDirectory(_cacheKey);
    }
    return directory.childFile(name);
  }
}
