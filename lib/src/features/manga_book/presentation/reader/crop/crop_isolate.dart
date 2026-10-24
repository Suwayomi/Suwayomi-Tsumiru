// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'border_crop.dart';

/// Tightly packed RGBA8888 with no row padding, ready for ui.decodeImageFromPixels.
class CroppedImageData {
  const CroppedImageData({
    required this.rgba,
    required this.width,
    required this.height,
  });

  final Uint8List rgba;
  final int width;
  final int height;
}

class _CropRequest {
  const _CropRequest(
    this.encodedBytes,
    this.threshold,
    this.targetWidth,
    this.targetHeight,
  );
  final Uint8List encodedBytes;
  final int threshold;
  final int? targetWidth;
  final int? targetHeight;
}

/// Returns null if decoding/cropping fails; downscales raw cropped pixels because decode-time caps cannot.
Future<CroppedImageData?> cropImageBytes(
  Uint8List encodedBytes, {
  int threshold = 20,
  int? targetWidth,
  int? targetHeight,
}) {
  return compute(
    _cropEntry,
    _CropRequest(encodedBytes, threshold, targetWidth, targetHeight),
  );
}

CroppedImageData? _cropEntry(_CropRequest req) {
  final decoded = img.decodeImage(req.encodedBytes);
  if (decoded == null) return null;

  final width = decoded.width;
  final height = decoded.height;
  final rgba = decoded.getBytes(order: img.ChannelOrder.rgba);

  final rect = findContentRect(rgba, width, height, threshold: req.threshold);
  if (rect == null) return null;

  final out = Uint8List(rect.width * rect.height * 4);
  var dst = 0;
  for (var y = rect.top; y < rect.bottom; y++) {
    final rowStart = (y * width + rect.left) * 4;
    final rowEnd = rowStart + rect.width * 4;
    out.setRange(dst, dst + (rowEnd - rowStart), rgba, rowStart);
    dst += rowEnd - rowStart;
  }

  // Only downscale; upscaling adds blur without recovering detail.
  final needsResize =
      (req.targetWidth != null && req.targetWidth! < rect.width) ||
      (req.targetHeight != null && req.targetHeight! < rect.height);
  if (!needsResize) {
    return CroppedImageData(rgba: out, width: rect.width, height: rect.height);
  }

  final resized = img.copyResize(
    img.Image.fromBytes(
      width: rect.width,
      height: rect.height,
      bytes: out.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    ),
    width: req.targetWidth,
    height: req.targetHeight,
  );
  return CroppedImageData(
    rgba: resized.getBytes(order: img.ChannelOrder.rgba),
    width: resized.width,
    height: resized.height,
  );
}
