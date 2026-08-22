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
/// crop for free — decoder-level border cropping.
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
    this.targetWidth,
    this.targetHeight,
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

  /// Decode-size cap (display px; see [ServerImage.memCacheWidth] /
  /// [memCacheHeight]), applied internally by this provider on both branches
  /// of [_load] — wrapping this provider in `ResizeImage` (as the un-cropped
  /// paths do) would silently do nothing here, because the cropped branch
  /// never calls the `decode` callback `ResizeImage` relies on (it starts
  /// from already-decoded raw pixels, not an encoded buffer).
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
      informationCollector: () =>
          <DiagnosticsNode>[ErrorDescription('Crop source: ${key.cacheKey}')],
    );
  }

  Future<ImageInfo> _load(ImageDecoderCallback decode) async {
    final bytes = await _fetchBytes();
    final cropped = await cropImageBytes(
      bytes,
      threshold: threshold,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    final ui.Image image = cropped != null
        ? await _decodeRgba(cropped)
        : await _decodeEncoded(bytes, decode);
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

  /// No border was found (or none was needed) — decode via the callback the
  /// engine handed [loadImage], so [targetWidth]/[targetHeight] still apply
  /// through the engine's own decode-time downscale (what `ResizeImage`
  /// itself builds on), instead of decoding at native resolution and never
  /// shrinking it.
  Future<ui.Image> _decodeEncoded(
    Uint8List bytes,
    ImageDecoderCallback decode,
  ) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await decode(
      buffer,
      getTargetSize: (targetWidth == null && targetHeight == null)
          ? null
          : (int intrinsicWidth, int intrinsicHeight) =>
                ui.TargetImageSize(width: targetWidth, height: targetHeight),
    );
    final frame = await codec.getNextFrame();
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
