// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:typed_data';

/// Content rectangle in PIXEL coords. [left]/[top] inclusive, [right]/[bottom]
/// exclusive, so [width]/[height] are the trimmed dimensions.
class ContentRect {
  const ContentRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final int left;
  final int top;
  final int right;
  final int bottom;

  int get width => right - left;
  int get height => bottom - top;

  @override
  String toString() => 'ContentRect($left, $top, $right, $bottom)';
}

// A line counts as a border line when at most this fraction of its pixels
// differ from the reference color — tolerates JPEG ringing along the edge.
const double _maxNonBorderFraction = 0.01;

// Reject a crop that keeps less than this fraction of the original area, which
// signals a runaway trim on a near-uniform page rather than a real border.
const double _minRetainedAreaFraction = 0.10;

/// Detects uniform border lines around the content and returns the inner
/// content rect, or null when nothing should be cropped.
///
/// The border reference color is the TOP-LEFT corner pixel; a pixel is a
/// "border" pixel when each of its R/G/B channels is within [threshold] of the
/// reference. Rows/columns that are (near-)entirely border pixels are trimmed
/// from each side; left/right are scanned only within the found [top,bottom)
/// band.
ContentRect? findContentRect(
  Uint8List rgba,
  int width,
  int height, {
  int threshold = 20,
}) {
  if (width <= 0 || height <= 0 || rgba.length < width * height * 4) {
    return null;
  }

  // Reference color = top-left corner pixel.
  final refR = rgba[0];
  final refG = rgba[1];
  final refB = rgba[2];

  bool isBorderPixel(int x, int y) {
    final i = (y * width + x) * 4;
    return (rgba[i] - refR).abs() <= threshold &&
        (rgba[i + 1] - refG).abs() <= threshold &&
        (rgba[i + 2] - refB).abs() <= threshold;
  }

  final maxRowMiss = (width * _maxNonBorderFraction).floor();

  bool isBorderRow(int y) {
    var miss = 0;
    for (var x = 0; x < width; x++) {
      if (!isBorderPixel(x, y) && ++miss > maxRowMiss) return false;
    }
    return true;
  }

  bool isBorderColumn(int x, int top, int bottom) {
    final band = bottom - top;
    final maxMiss = (band * _maxNonBorderFraction).floor();
    var miss = 0;
    for (var y = top; y < bottom; y++) {
      if (!isBorderPixel(x, y) && ++miss > maxMiss) return false;
    }
    return true;
  }

  var top = 0;
  while (top < height && isBorderRow(top)) {
    top++;
  }
  // Whole image is border → nothing meaningful to keep.
  if (top >= height) return null;

  var bottom = height;
  while (bottom > top && isBorderRow(bottom - 1)) {
    bottom--;
  }

  var left = 0;
  while (left < width && isBorderColumn(left, top, bottom)) {
    left++;
  }
  var right = width;
  while (right > left && isBorderColumn(right - 1, top, bottom)) {
    right--;
  }

  // Nothing trimmed on any side → no border.
  if (top == 0 && bottom == height && left == 0 && right == width) {
    return null;
  }

  final newWidth = right - left;
  final newHeight = bottom - top;
  if (newWidth <= 0 || newHeight <= 0) return null;

  // Runaway-crop guard.
  final retained = (newWidth * newHeight) / (width * height);
  if (retained < _minRetainedAreaFraction) return null;

  return ContentRect(left: left, top: top, right: right, bottom: bottom);
}
