// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../../../../utils/avif/avif_codec.dart';
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
    this.textureLimit,
  );
  final Uint8List encodedBytes;
  final int threshold;
  final int? targetWidth;
  final int? targetHeight;
  final int? textureLimit;
}

/// Returns null if decoding/cropping fails; downscales raw cropped pixels because decode-time caps cannot.
Future<CroppedImageData?> cropImageBytes(
  Uint8List encodedBytes, {
  int threshold = 20,
  int? targetWidth,
  int? targetHeight,
  int? textureLimit,
}) {
  return compute(
    _cropEntry,
    _CropRequest(encodedBytes, threshold, targetWidth, targetHeight, textureLimit),
  );
}

CroppedImageData? _cropEntry(_CropRequest req) {
  final decoded = img.decodeImage(normalizeAvifBytesSync(req.encodedBytes));
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

  var targetWidth = req.targetWidth;
  var targetHeight = req.targetHeight;
  final limit = req.textureLimit;
  if (limit != null && math.max(rect.width, rect.height) > limit) {
    final scale = math.min(
      limit / math.max(rect.width, rect.height),
      math.min(
        (targetWidth ?? rect.width) / rect.width,
        (targetHeight ?? rect.height) / rect.height,
      ),
    );
    targetWidth = math.max(1, (rect.width * scale).round());
    targetHeight = math.max(1, (rect.height * scale).round());
  }

  // Only downscale; upscaling adds blur without recovering detail.
  final needsResize =
      (targetWidth != null && targetWidth < rect.width) ||
      (targetHeight != null && targetHeight < rect.height);
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
    width: targetWidth,
    height: targetHeight,
  );
  return CroppedImageData(
    rgba: resized.getBytes(order: img.ChannelOrder.rgba),
    width: resized.width,
    height: resized.height,
  );
}
