// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

/// Formats a byte count as a human-readable string (e.g. "1.5 GB").
String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  if (bytes <= 0) return '0 B';
  var b = bytes.toDouble();
  var i = 0;
  while (b >= 1024 && i < units.length - 1) {
    b /= 1024;
    i++;
  }
  return i == 0 ? '${b.toInt()} B' : '${b.toStringAsFixed(1)} ${units[i]}';
}
