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
CacheManager createCoverCacheManager({String? serverOrigin}) => _CoverCacheManager(
      Config(
        'tsumiruCovers',
        stalePeriod: const Duration(days: 90),
        maxNrOfCacheObjects: 5000,
        fileSystem: _AppSupportFileSystem('tsumiruCovers'),
      ),
    );

/// A cover on disk is shown, full stop — its age is never a reason to go back
/// to the server.
///
/// The stock manager re-downloads an expired entry every time it is displayed,
/// and the expiry comes from the server's own cache headers (about ten days
/// for a Suwayomi thumbnail), so scrolling a library quietly re-fetched every
/// cover past its date. Covers change when the user asks for new metadata, not
/// on a clock: an explicit refresh evicts the entry, and the next load fetches
/// it because there is no copy left — not because it went stale.
class _CoverCacheManager extends CacheManager {
  _CoverCacheManager(super.config);

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) async* {
    final cached = await getFileFromCache(key ?? url);
    if (cached != null) {
      yield cached;
      return;
    }
    yield* super.getFileStream(
      url,
      key: key,
      headers: headers,
      withProgress: withProgress,
    );
  }
}

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
