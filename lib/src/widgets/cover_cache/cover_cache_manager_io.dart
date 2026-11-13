// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io' as io;

import 'package:file/file.dart' hide FileSystem;
import 'package:file/local.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../utils/avif/avif_file_io.dart';
import 'cover_cache_key.dart';

export '../../utils/avif/avif_header.dart' show isAvifHeader;

const _transcoderChannel = MethodChannel('tsumiru/image_transcoder');
final _inFlightFileTranscodes = <String, Future<void>>{};
final _failedFileTranscodes = <String, io.FileStat>{};
Future<bool>? _androidSupportsAvifDecode;

Future<bool> _loadAndroidSupportsAvifDecode() async {
  try {
    final sdkInt = await _transcoderChannel.invokeMethod<int>('sdkInt');
    return (sdkInt ?? 0) >= 31;
  } catch (_) {
    return false;
  }
}

Future<void> _transcodeAvif(io.File file) async {
  final path = file.path;
  io.FileStat stat;
  try {
    if (!await file.exists()) return;
    stat = await file.stat();
  } catch (_) {
    return;
  }
  final failed = _failedFileTranscodes[path];
  if (failed != null && sameFileStat(failed, stat)) {
    return;
  }
  try {
    if (!io.Platform.isAndroid) {
      if (await transcodeAvifFileToPng(file)) {
        _failedFileTranscodes.remove(path);
      } else {
        _failedFileTranscodes[path] = stat;
      }
      return;
    }
    if (!await isAvifFile(file)) {
      _failedFileTranscodes.remove(path);
      return;
    }
    final supported = await (_androidSupportsAvifDecode ??=
        _loadAndroidSupportsAvifDecode());
    if (!supported) return;
    final converted = await _transcoderChannel.invokeMethod<bool>(
      'transcodeFileToJpeg',
      {'path': path},
    );
    if (converted == true) {
      _failedFileTranscodes.remove(path);
    } else {
      _failedFileTranscodes[path] = stat;
    }
  } catch (_) {
    _failedFileTranscodes[path] = stat;
  }
}

Future<void> _transcodeAvifIfNeeded(io.File file) {
  if (!io.Platform.isAndroid && !io.Platform.isLinux) {
    return Future.value();
  }
  return transcodeAvifInFlight(file.path, () => _transcodeAvif(file));
}

@visibleForTesting
Future<void> transcodeAvifInFlight(
  String path,
  Future<void> Function() transcode,
) {
  return _inFlightFileTranscodes[path] ??= transcode().whenComplete(() {
    _inFlightFileTranscodes.remove(path);
  });
}

Future<FileInfo> _transcodeAvifInfo(FileInfo info) async {
  await _transcodeAvifIfNeeded(io.File(info.file.path));
  return info;
}

CacheManager createServerPageCacheManager() {
  if (!io.Platform.isLinux) return DefaultCacheManager();
  final manager = _serverPageCacheManager;
  if (manager != null) return manager;
  final config = Config(DefaultCacheManager.key);
  return _serverPageCacheManager = _ServerPageCacheManager(config);
}

CacheManager? _serverPageCacheManager;

mixin _AvifTranscodingCacheManager on CacheManager {
  @override
  Future<FileInfo?> getFileFromCache(
    String key, {
    bool ignoreMemCache = false,
  }) async {
    final info = await super.getFileFromCache(
      key,
      ignoreMemCache: ignoreMemCache,
    );
    return info == null ? null : await _transcodeAvifInfo(info);
  }

  @override
  Future<File> getSingleFile(
    String url, {
    String? key,
    Map<String, String>? headers,
  }) async {
    final file = await super.getSingleFile(url, key: key, headers: headers);
    await _transcodeAvifIfNeeded(io.File(file.path));
    return file;
  }

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) async* {
    await for (final response in super.getFileStream(
      url,
      key: key,
      headers: headers,
      withProgress: withProgress,
    )) {
      yield response is FileInfo
          ? await _transcodeAvifInfo(response)
          : response;
    }
  }
}

CacheManager createCoverCacheManager({String? serverOrigin}) =>
    _CoverCacheManager(
      Config(
        'tsumiruCovers',
        stalePeriod: const Duration(days: 90),
        maxNrOfCacheObjects: 5000,
        fileSystem: _AppSupportFileSystem('tsumiruCovers'),
      ),
    );

/// Covers never revalidate while their version holds; a new version first asks
/// the server whether the previous version's file is still current (ETag).
class _CoverCacheManager extends CacheManager
    with _AvifTranscodingCacheManager {
  _CoverCacheManager(super.config);

  final _carryOvers = <String, Future<FileInfo?>>{};

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) async* {
    final cacheKey = key ?? url;
    final cached = await getFileFromCache(cacheKey);
    if (cached != null) {
      yield cached;
      return;
    }
    final carried = await _carryOverPreviousVersion(url, cacheKey, headers);
    if (carried != null) {
      yield carried;
      return;
    }
    yield* super.getFileStream(
      url,
      key: key,
      headers: headers,
      withProgress: withProgress,
    );
  }

  @override
  Future<FileInfo> downloadFile(
    String url, {
    String? key,
    Map<String, String>? authHeaders,
    bool force = false,
  }) async {
    if (!force) {
      final carried = await _carryOverPreviousVersion(
        url,
        key ?? url,
        authHeaders,
      );
      if (carried != null) return carried;
    }
    return super.downloadFile(
      url,
      key: key,
      authHeaders: authHeaders,
      force: force,
    );
  }

  /// Null when there is nothing to carry over, so the caller downloads as usual.
  Future<FileInfo?> _carryOverPreviousVersion(
    String url,
    String key,
    Map<String, String>? headers,
  ) {
    final unversioned = unversionedCoverKey(key);
    if (unversioned == null) return Future.value();
    return _carryOvers[key] ??=
        carryOverCoverVersion(
          cache: this,
          url: url,
          key: key,
          unversionedKey: unversioned,
          headers: headers,
        ).whenComplete(() {
          _carryOvers.remove(key);
        });
  }
}

/// Moves the previous version of [key]'s cover to [key] when the server
/// answers 304 to its ETag, or stores the 200 body; the old entry is then
/// dropped. Null when no previous version with an ETag exists or the
/// exchange fails for a non-network reason; network errors are rethrown so a
/// failed request is not sent twice.
@visibleForTesting
Future<FileInfo?> carryOverCoverVersion({
  required CacheManager cache,
  required String url,
  required String key,
  required String unversionedKey,
  Map<String, String>? headers,
}) async {
  final ({CacheObject entry, File file})? found;
  try {
    found = await cache.store.retrieveCacheData(key) != null
        ? null
        : await _previousCoverVersion(cache, key, unversionedKey);
  } catch (_) {
    return null;
  }
  if (found == null) return null;
  final (:entry, file: previousFile) = found;
  final eTag = entry.eTag!;
  final response = await cache.config.fileService.get(
    url,
    headers: {...?headers, io.HttpHeaders.ifNoneMatchHeader: eTag},
  );
  try {
    final maxAge = response.validTill.difference(DateTime.now());
    switch (response.statusCode) {
      case io.HttpStatus.notModified:
        await response.content.drain<void>();
        await cache.putFileStream(
          url,
          previousFile.openRead(),
          key: key,
          eTag: response.eTag ?? eTag,
          maxAge: maxAge,
          fileExtension: _extensionOf(entry.relativePath),
        );
      case io.HttpStatus.ok:
        await cache.putFileStream(
          url,
          response.content,
          key: key,
          eTag: response.eTag,
          maxAge: maxAge,
          fileExtension: _withoutDot(response.fileExtension),
        );
      default:
        await response.content.drain<void>();
        return null;
    }
    await cache.removeFile(entry.key);
    return await cache.getFileFromCache(key);
  } catch (_) {
    return null;
  }
}

/// Most recently used other version of the same cover that has an ETag and a file.
Future<({CacheObject entry, File file})?> _previousCoverVersion(
  CacheManager cache,
  String key,
  String unversionedKey,
) async {
  final prefix = '$unversionedKey$coverVersionMarker';
  final repo = cache.config.repo;
  final List<CacheObject> candidates;
  final db = repo is CacheObjectProvider ? repo.db : null;
  if (db != null) {
    // instr() is an exact, case-sensitive prefix test, unlike LIKE.
    candidates = CacheObject.fromMapList(
      await db.query(
        'cacheObject',
        where:
            '${CacheObject.columnKey} = ? OR '
            'instr(${CacheObject.columnKey}, ?) = 1',
        whereArgs: [unversionedKey, prefix],
      ),
    );
  } else {
    candidates = await repo.getAllObjects();
  }
  CacheObject? best;
  for (final candidate in candidates) {
    final k = candidate.key;
    if (k == key || (k != unversionedKey && !k.startsWith(prefix))) continue;
    final eTag = candidate.eTag;
    if (eTag == null || eTag.isEmpty) continue;
    final touched = candidate.touched;
    final bestTouched = best?.touched;
    if (best == null ||
        (touched != null &&
            (bestTouched == null || touched.isAfter(bestTouched)))) {
      best = candidate;
    }
  }
  if (best == null) return null;
  final file = await cache.config.fileSystem.createFile(best.relativePath);
  return await file.exists() ? (entry: best, file: file) : null;
}

String _extensionOf(String relativePath) {
  final ext = p.extension(relativePath);
  return ext.isEmpty ? 'file' : _withoutDot(ext);
}

String _withoutDot(String extension) {
  final ext = extension.startsWith('.') ? extension.substring(1) : extension;
  return ext.isEmpty ? 'file' : ext;
}

class _ServerPageCacheManager extends CacheManager
    with _AvifTranscodingCacheManager {
  _ServerPageCacheManager(super.config);
}

/// Package IOFileSystem layout rooted in durable application-support.
class _AppSupportFileSystem implements FileSystem {
  _AppSupportFileSystem(this._cacheKey)
    : _fileDir = _createDirectory(_cacheKey);

  final Future<Directory> _fileDir;
  final String _cacheKey;

  static Future<Directory> _createDirectory(String key) async {
    final baseDir = await getApplicationSupportDirectory();
    final directory = const LocalFileSystem().directory(
      p.join(baseDir.path, key),
    );
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
