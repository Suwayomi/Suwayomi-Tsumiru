// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io' as io;

import 'package:file/file.dart' hide FileSystem;
import 'package:file/local.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _transcoderChannel = MethodChannel('tsumiru/image_transcoder');
final _inFlightFileTranscodes = <String, Future<void>>{};

bool _isFtypContainer(List<int> bytes) {
  return bytes.length >= 12 &&
      bytes[4] == 0x66 && // f
      bytes[5] == 0x74 && // t
      bytes[6] == 0x79 && // y
      bytes[7] == 0x70;   // p
}

Future<void> _transcodeCachedFileIfNeeded(io.File file) {
  if (!io.Platform.isAndroid) {
    return Future.value();
  }

  final path = file.path;
  final inFlight = _inFlightFileTranscodes[path];
  if (inFlight != null) {
    return inFlight;
  }

  final transcodeFuture = () async {
    try {
      if (!await file.exists()) {
        return;
      }

      final raf = await file.open(mode: io.FileMode.read);
      final header = await raf.read(12);
      await raf.close();

      if (!_isFtypContainer(header)) {
        return;
      }

      await _transcoderChannel.invokeMethod<bool>(
        'transcodeFileToJpeg',
        {'path': path},
      );
    } catch (e) {
      if (kDebugMode) {
        print('NATIVE TRANSCODE ERROR: $e');
      }
    } finally {
      _inFlightFileTranscodes.remove(path);
    }
  }();

  _inFlightFileTranscodes[path] = transcodeFuture;
  return transcodeFuture;
}

/// Cover/icon image cache that survives OS cache pressure.
///
/// The default cache manager keeps at most 200 files in the OS *temp* dir —
/// on mobile, background memory pressure wipes temp aggressively, turning every
/// library visit into a network re-fetch.
///
/// Stored in application-support instead so covers stay durable across app
/// launches. Keys can be salted with the server origin when multi-server
/// support needs isolated caches per instance.
CacheManager createCoverCacheManager({String? serverOrigin}) =>
    _CoverCacheManager(
      Config(
        serverOrigin != null
            ? 'sorayomi-covers-${serverOrigin.hashCode}'
            : 'sorayomi-covers',
        stalePeriod: const Duration(days: 30),
        maxNrOfCacheObjects: 2000,
        repo: JsonCacheInfoRepository(
          databaseName: serverOrigin != null
              ? 'sorayomi-covers-${serverOrigin.hashCode}'
              : 'sorayomi-covers',
        ),
        fileSystem: _AppSupportFileSystem(
          serverOrigin != null
              ? 'sorayomi-covers-${serverOrigin.hashCode}'
              : 'sorayomi-covers',
        ),
      ),
    );

class _CoverCacheManager extends CacheManager {
  _CoverCacheManager(super.config);

  Future<FileInfo> _processFileInfo(FileInfo info) async {
    if (io.Platform.isAndroid) {
      await _transcodeCachedFileIfNeeded(io.File(info.file.path));
    }
    return info;
  }

  @override
  Future<FileInfo?> getFileFromCache(
      String key, {
        bool ignoreMemCache = false,
      }) async {
    final info = await super.getFileFromCache(
      key,
      ignoreMemCache: ignoreMemCache,
    );
    if (info != null) {
      return _processFileInfo(info);
    }
    return null;
  }

  @override
  Future<File> getSingleFile(
      String url, {
        String? key,
        Map<String, String>? headers,
      }) async {
    final file = await super.getSingleFile(url, key: key, headers: headers);
    if (io.Platform.isAndroid) {
      await _transcodeCachedFileIfNeeded(io.File(file.path));
    }
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
      if (response is FileInfo) {
        yield await _processFileInfo(response);
      } else {
        yield response;
      }
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
    return const LocalFileSystem().directory(p.join(baseDir.path, key));
  }

  @override
  Future<Directory> get directory => _fileDir;

  @override
  Future<File> createFile(String name) async {
    final directory = await _fileDir;
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory.childFile(name);
  }
}