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
  const _CropRequest(this.encodedBytes, this.threshold);
  final Uint8List encodedBytes;
  final int threshold;
}

/// Decodes [encodedBytes], detects borders, and returns the cropped RGBA in a
/// background isolate. Returns null when the image can't be decoded or no
/// border was found (caller falls back to the uncropped image).
Future<CroppedImageData?> cropImageBytes(
  Uint8List encodedBytes, {
  int threshold = 20,
}) {
  return compute(_cropEntry, _CropRequest(encodedBytes, threshold));
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

  return CroppedImageData(rgba: out, width: rect.width, height: rect.height);
}
