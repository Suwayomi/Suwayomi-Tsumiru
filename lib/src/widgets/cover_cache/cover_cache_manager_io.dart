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

import '../../utils/avif/avif_cache_transcode_io.dart';
import '../../utils/avif/avif_header.dart';

export '../../utils/avif/avif_header.dart' show isAvifHeader;

const _transcoderChannel = MethodChannel('tsumiru/image_transcoder');
final _inFlightFileTranscodes = <String, Future<void>>{};
final _failedFileTranscodes = <String, _FileIdentity>{};
Future<bool>? _androidSupportsAvifDecode;

/// Identifies the bytes that failed, so a refreshed file is retried.
class _FileIdentity {
  const _FileIdentity(this.length, this.modified, this.changed);

  factory _FileIdentity.of(io.FileStat stat) => _FileIdentity(
    stat.size,
    stat.modified.millisecondsSinceEpoch,
    stat.changed.millisecondsSinceEpoch,
  );

  final int length;
  final int modified;
  final int changed;

  bool matches(io.FileStat stat) =>
      stat.size == length &&
      stat.modified.millisecondsSinceEpoch == modified &&
      stat.changed.millisecondsSinceEpoch == changed;
}

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
  if (failed != null && failed.matches(stat)) {
    return;
  }
  try {
    final header = await file
        .openRead(0, avifHeaderProbeBytes)
        .expand((chunk) => chunk)
        .toList();
    if (!isAvifHeader(header)) {
      _failedFileTranscodes.remove(path);
      return;
    }
    final converted = io.Platform.isAndroid
        ? await _transcodeAndroidAvif(path)
        : await transcodeAvifFileToPng(file);
    if (converted == true) {
      _failedFileTranscodes.remove(path);
    } else if (converted == false) {
      _failedFileTranscodes[path] = _FileIdentity.of(stat);
    }
  } catch (_) {
    _failedFileTranscodes[path] = _FileIdentity.of(stat);
  }
}

/// Null when the Android platform has no AVIF decoder and no work was needed.
Future<bool?> _transcodeAndroidAvif(String path) async {
  final supported = await (_androidSupportsAvifDecode ??=
      _loadAndroidSupportsAvifDecode());
  if (!supported) {
    return null;
  }
  final transcoded = await _transcoderChannel.invokeMethod<bool>(
    'transcodeFileToJpeg',
    {'path': path},
  );
  return transcoded == true;
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

/// Reader pages keep the default cache key; only Linux adds AVIF conversion.
CacheManager createServerPageCacheManager() {
  if (!io.Platform.isLinux) return DefaultCacheManager();
  return _serverPageCacheManager ??= _ServerPageCacheManager(
    Config(DefaultCacheManager.key),
  );
}

CacheManager? _serverPageCacheManager;

/// Convert AVIF before bytes reach the engine decoders.
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

/// Durable app-support cover cache, separate from reader pages and immune to OS temp cleanup.
CacheManager createCoverCacheManager({String? serverOrigin}) =>
    _CoverCacheManager(
      Config(
        'tsumiruCovers',
        stalePeriod: const Duration(days: 90),
        maxNrOfCacheObjects: 5000,
        fileSystem: _AppSupportFileSystem('tsumiruCovers'),
      ),
    );

/// Ignore age until explicit eviction; AVIF is pre-converted for the platform decoder.
class _CoverCacheManager extends CacheManager
    with _AvifTranscodingCacheManager {
  _CoverCacheManager(super.config);

  /// Keep the durable-cover fast path: a cache hit is final and never refetched.
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
