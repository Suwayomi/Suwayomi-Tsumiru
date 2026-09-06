// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'border_crop.dart';

/// Raw RGBA8888 of the cropped region, tightly packed (no row padding) — ready
/// for `ui.decodeImageFromPixels(rgba, width, height, PixelFormat.rgba8888)`.
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

// Sendable argument bundle for [compute].
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

/// Decodes [encodedBytes], detects borders, and returns the cropped RGBA in a
/// background isolate. Returns null when the image can't be decoded or no
/// border was found (caller falls back to the uncropped image).
///
/// [targetWidth]/[targetHeight] (display px, one may be null to preserve
/// aspect) downscale the cropped region in this same isolate call — the decode
/// cap [ServerImage] applies to the un-cropped path can't reach this one
/// (these are already-decoded raw pixels, not an encoded buffer the engine's
/// decode-time resize can act on), so it has to happen here instead.
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

  // Slice the source RGBA buffer directly into a tightly-packed output.
  final out = Uint8List(rect.width * rect.height * 4);
  var dst = 0;
  for (var y = rect.top; y < rect.bottom; y++) {
    final rowStart = (y * width + rect.left) * 4;
    final rowEnd = rowStart + rect.width * 4;
    out.setRange(dst, dst + (rowEnd - rowStart), rgba, rowStart);
    dst += rowEnd - rowStart;
  }

  // Only ever downscale — an upscale would blur a crop that's already
  // smaller than the cap for no benefit.
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
