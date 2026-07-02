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

import 'crop_isolate.dart';

/// Decoder-level auto-crop: fetches the page's encoded bytes through the SAME
/// cache entry [ServerImage] uses ([cacheKey] + [headers]), trims solid borders
/// off-thread ([cropImageBytes]), and yields the cropped frame. When no border
/// is found the original image is decoded unchanged. Because it's an
/// [ImageProvider], every consumer (single/double/split/rotate/webtoon) gets
/// crop for free — mirroring Mihon's decoder-level `cropBorders`.
///
/// Identity ([==]/[hashCode]) keys Flutter's [ImageCache], so a re-scrolled page
/// reuses the already-cropped decode instead of re-running the isolate.
@immutable
class CroppedImageProvider extends ImageProvider<CroppedImageProvider> {
  const CroppedImageProvider({
    required this.fetchUrl,
    required this.cacheKey,
    this.headers,
    this.localPath,
    this.threshold = 20,
    this.scale = 1.0,
  });

  /// URL fetched when the bytes aren't already cached (token-appended for
  /// ui_login); ignored for [localPath] pages.
  final String fetchUrl;

  /// Stable cache key shared with [ServerImage] (the token-less base URL), so
  /// the byte fetch hits the same [DefaultCacheManager] entry.
  final String cacheKey;
  final Map<String, String>? headers;

  /// Offline page: bytes come straight off disk, no network.
  final String? localPath;
  final int threshold;
  final double scale;

  @override
  Future<CroppedImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<CroppedImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    CroppedImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(
      key._load(),
      informationCollector: () =>
          <DiagnosticsNode>[ErrorDescription('Crop source: ${key.cacheKey}')],
    );
  }

  Future<ImageInfo> _load() async {
    final bytes = await _fetchBytes();
    final cropped = await cropImageBytes(bytes, threshold: threshold);
    final ui.Image image = cropped != null
        ? await _decodeRgba(cropped)
        : await _decodeEncoded(bytes);
    return ImageInfo(image: image, scale: scale);
  }

  Future<Uint8List> _fetchBytes() async {
    if (localPath != null) return File(localPath!).readAsBytes();
    final file = await DefaultCacheManager().getSingleFile(
      fetchUrl,
      key: cacheKey,
      headers: headers ?? const <String, String>{},
    );
    return file.readAsBytes();
  }

  Future<ui.Image> _decodeRgba(CroppedImageData data) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      data.rgba,
      data.width,
      data.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  Future<ui.Image> _decodeEncoded(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  @override
  bool operator ==(Object other) =>
      other is CroppedImageProvider &&
      other.cacheKey == cacheKey &&
      other.localPath == localPath &&
      other.threshold == threshold &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(cacheKey, localPath, threshold, scale);

  @override
  String toString() => 'CroppedImageProvider($cacheKey, t:$threshold)';
}
