// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Decode size that just covers a [boxWidth] × [boxHeight] box while keeping
/// the image's aspect ratio, like a browser drawing `object-fit: cover`.
///
/// Returns null when the image is already no larger than that, so it decodes
/// at its own size and is never scaled up.
ui.TargetImageSize? coverDecodeSize(
  int imageWidth,
  int imageHeight,
  int boxWidth,
  int boxHeight,
) {
  if (imageWidth <= 0 || imageHeight <= 0) return null;
  final scale = math.max(boxWidth / imageWidth, boxHeight / imageHeight);
  if (scale >= 1) return null;
  return ui.TargetImageSize(
    width: math.max(1, (imageWidth * scale).ceil()),
    height: math.max(1, (imageHeight * scale).ceil()),
  );
}

/// Decodes [imageProvider] just large enough to cover [width] × [height]
/// physical pixels, for images drawn with [BoxFit.cover].
///
/// [ResizeImage] given only a width keeps the aspect ratio, so a cover wider
/// than its tile decodes too short and [BoxFit.cover] then has to enlarge it
/// to fill the tile's height, which blurs it. Given both sides it stretches the
/// image to exactly that size instead.
class CoverDecodeImage extends ImageProvider<CoverDecodeImageKey> {
  const CoverDecodeImage(
    this.imageProvider, {
    required this.width,
    required this.height,
  });

  final ImageProvider imageProvider;
  final int width;
  final int height;

  @override
  Future<CoverDecodeImageKey> obtainKey(ImageConfiguration configuration) {
    // Stay synchronous when the wrapped provider is, as ResizeImage does, so
    // covers already in the image cache draw on the first frame.
    Completer<CoverDecodeImageKey>? completer;
    SynchronousFuture<CoverDecodeImageKey>? result;
    imageProvider.obtainKey(configuration).then((Object key) {
      final coverKey = CoverDecodeImageKey(key, width, height);
      if (completer == null) {
        result = SynchronousFuture<CoverDecodeImageKey>(coverKey);
      } else {
        completer.complete(coverKey);
      }
    });
    if (result != null) return result!;
    completer = Completer<CoverDecodeImageKey>();
    return completer.future;
  }

  @override
  ImageStreamCompleter loadImage(
    CoverDecodeImageKey key,
    ImageDecoderCallback decode,
  ) {
    Future<ui.Codec> decodeToCover(
      ui.ImmutableBuffer buffer, {
      ui.TargetImageSizeCallback? getTargetSize,
    }) {
      assert(
        getTargetSize == null,
        'CoverDecodeImage cannot wrap a provider that sets its own target size.',
      );
      return decode(
        buffer,
        getTargetSize: (int intrinsicWidth, int intrinsicHeight) =>
            coverDecodeSize(intrinsicWidth, intrinsicHeight, width, height) ??
            ui.TargetImageSize(),
      );
    }

    final completer = imageProvider.loadImage(key.providerKey, decodeToCover);
    // The wrapped provider evicts only its own key on failure; drop ours too,
    // as ResizeImage does, so a failed cover is fetched again (reload button,
    // remount) instead of replaying the cached error.
    completer.addEphemeralErrorListener((Object exception, StackTrace? stack) {
      // A microtask, so the image cache has started tracking the key.
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
    });
    return completer;
  }
}

@immutable
class CoverDecodeImageKey {
  const CoverDecodeImageKey(this.providerKey, this.width, this.height);

  final Object providerKey;
  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is CoverDecodeImageKey &&
      other.providerKey == providerKey &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(providerKey, width, height);
}
