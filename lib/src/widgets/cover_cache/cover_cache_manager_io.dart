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

const _transcoderChannel = MethodChannel('tsumiru/image_transcoder');
const _avifHeaderBytes = 256;
final _inFlightFileTranscodes = <String, Future<void>>{};
final _failedFileTranscodes = <String>{};
Future<bool>? _androidSupportsAvifDecode;

bool isAvifHeader(List<int> bytes) {
  if (bytes.length < 12 ||
      String.fromCharCodes(bytes.sublist(4, 8)) != 'ftyp') {
    return false;
  }
  final boxSize =
      (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
  if (boxSize < 16) {
    return false;
  }
  final end = boxSize < bytes.length ? boxSize : bytes.length;
  bool isAvifBrand(int offset) {
    final brand = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    return brand == 'avif' || brand == 'avis';
  }

  if (isAvifBrand(8)) {
    return true;
  }
  for (var offset = 16; offset + 4 <= end; offset += 4) {
    if (isAvifBrand(offset)) {
      return true;
    }
  }
  return false;
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
  try {
    final supported = await (_androidSupportsAvifDecode ??=
        _loadAndroidSupportsAvifDecode());
    if (!supported || !await file.exists()) {
      return;
    }
    final header = await file
        .openRead(0, _avifHeaderBytes)
        .expand((chunk) => chunk)
        .toList();
    if (!isAvifHeader(header)) {
      return;
    }
    final transcoded = await _transcoderChannel.invokeMethod<bool>(
      'transcodeFileToJpeg',
      {'path': path},
    );
    if (transcoded != true) {
      _failedFileTranscodes.add(path);
    }
  } catch (_) {
    _failedFileTranscodes.add(path);
  }
}

Future<void> _transcodeAvifIfNeeded(io.File file) {
  final path = file.path;
  if (!io.Platform.isAndroid || _failedFileTranscodes.contains(path)) {
    return Future.value();
  }
  return transcodeAvifInFlight(path, () => _transcodeAvif(file));
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
CacheManager createCoverCacheManager({String? serverOrigin}) =>
    _CoverCacheManager(
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
///
/// On Android 12 and newer, AVIF covers are transcoded to JPEG in place, since
/// the platform AV1 decoder stutters or crashes on them.
class _CoverCacheManager extends CacheManager {
  _CoverCacheManager(super.config);

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
    final cached = await getFileFromCache(key ?? url);
    if (cached != null) {
      yield cached;
      return;
    }
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

/// Same layout as the package's IOFileSystem, but rooted in
/// application-support instead of the OS temp dir.
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
