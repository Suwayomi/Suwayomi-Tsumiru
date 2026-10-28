// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../../../../../utils/avif/avif_codec.dart';
import '../../../../../utils/texture_limit.dart';
import '../../../../../widgets/cover_cache/server_page_cache_manager.dart';
import 'crop_isolate.dart';

/// Shares ServerImage byte-cache identity and crops off-thread; uncropped images decode unchanged.
@immutable
class CroppedImageProvider extends ImageProvider<CroppedImageProvider> {
  const CroppedImageProvider({
    required this.fetchUrl,
    required this.cacheKey,
    this.headers,
    this.cacheManager,
    this.localPath,
    this.threshold = 20,
    this.scale = 1.0,
    this.targetWidth,
    this.targetHeight,
  });

  /// Token-appended fetch URL; ignored for [localPath] pages.
  final String fetchUrl;

  /// Token-free cache key shared with ServerImage and DefaultCacheManager.
  final String cacheKey;
  final Map<String, String>? headers;
  final CacheManager? cacheManager;

  /// Offline page: bytes come straight off disk, no network.
  final String? localPath;
  final int threshold;
  final double scale;

  /// ResizeImage cannot resize the raw-pixel crop branch; apply display-pixel caps internally.
  final int? targetWidth;
  final int? targetHeight;

  @override
  Future<CroppedImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<CroppedImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    CroppedImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(
      key._load(decode),
      informationCollector: () => <DiagnosticsNode>[
        ErrorDescription('Crop source: ${key.cacheKey}'),
      ],
    );
  }

  Future<ImageInfo> _load(ImageDecoderCallback decode) async {
    final bytes = await _fetchBytes();
    final cropped = await cropImageBytes(
      bytes,
      threshold: threshold,
      textureLimit: await deviceTextureLimit,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    final ui.Image image = cropped != null
        ? await _decodeRgba(cropped)
        : await _decodeEncoded(bytes, decode);
    return ImageInfo(image: image, scale: scale);
  }

  Future<Uint8List> _fetchBytes() async {
    final Uint8List bytes;
    if (localPath != null) {
      bytes = await File(localPath!).readAsBytes();
    } else {
      final file = await (cacheManager ?? createServerPageCacheManager())
          .getSingleFile(
            fetchUrl,
            key: cacheKey,
            headers: headers ?? const <String, String>{},
          );
      bytes = await file.readAsBytes();
    }
    return normalizeAvifBytes(bytes);
  }

  Future<ui.Image> _decodeRgba(CroppedImageData data) async {
    final target = textureLimitedSize(
      data.width, data.height, await deviceTextureLimit,
    );
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      data.rgba,
      data.width,
      data.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
      targetWidth: target?.width,
      targetHeight: target?.height,
    );
    return completer.future;
  }

  /// Use the engine decode callback so size caps also apply when no border is cropped.
  Future<ui.Image> _decodeEncoded(
    Uint8List bytes,
    ImageDecoderCallback decode,
  ) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await decodeWithinTextureLimit(
      buffer,
      decode,
      getTargetSize: (targetWidth == null && targetHeight == null)
          ? null
          : (int intrinsicWidth, int intrinsicHeight) =>
                ui.TargetImageSize(width: targetWidth, height: targetHeight),
    );
    final frame = await codec.getNextFrame().whenComplete(codec.dispose);
    return frame.image;
  }

  @override
  bool operator ==(Object other) =>
      other is CroppedImageProvider &&
      other.cacheKey == cacheKey &&
      other.localPath == localPath &&
      other.threshold == threshold &&
      other.scale == scale &&
      other.targetWidth == targetWidth &&
      other.targetHeight == targetHeight;

  @override
  int get hashCode => Object.hash(
    cacheKey,
    localPath,
    threshold,
    scale,
    targetWidth,
    targetHeight,
  );

  @override
  String toString() => 'CroppedImageProvider($cacheKey, t:$threshold)';
}
